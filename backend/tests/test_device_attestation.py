#!/usr/bin/env python3
"""
Key Attestation 验证器单元测试。

用自签证书链构造"假 attestation 证据"（pyasn1 编码 KeyDescription 扩展），
覆盖 verify_key_attestation 的全部通过/拒绝路径——真机 TEE 证书链无法
离线构造，但 verifier 的解析与判定逻辑可完整验证：

- 链签名验证 + 可信根锚定
- challenge 匹配（防重放）
- 硬件级安全等级要求（software 拒绝）
- 官方 APK 签名摘要比对（魔改拒绝）
- authorization list 含未知 context tag 时的健壮性（真实链形态）
"""

import hashlib
from datetime import UTC, datetime

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID, ObjectIdentifier
from pyasn1.codec.der.encoder import encode as der_encode

from app.config import settings
from app.exceptions import AuthenticationError
from app.services import device_attestation as att
from app.services.device_attestation import verify_key_attestation

ATTESTATION_OID = ObjectIdentifier("1.3.6.1.4.1.11129.2.1.17")

CHALLENGE = "test-nonce-1234567890"
APP_SIG_SHA256 = "ab" * 32  # 测试用"官方签名摘要"


def _ec_key():
    return ec.generate_private_key(ec.SECP256R1())


def _make_cert(subject_key, signer_key, issuer_name, subject_name, ca=False):
    name_issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, issuer_name)])
    name_subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, subject_name)])
    builder = (
        x509.CertificateBuilder()
        .subject_name(name_subject)
        .issuer_name(name_issuer)
        .public_key(subject_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.now(UTC))
        .not_valid_after(datetime.now(UTC) + __import__("datetime").timedelta(days=365))
    )
    if ca:
        builder = builder.add_extension(
            x509.BasicConstraints(ca=True, path_length=None), critical=True
        )
    return builder.sign(signer_key, hashes.SHA256())


def univ_seq(items):
    from pyasn1.type import univ

    seq = univ.SequenceOf()
    for i, item in enumerate(items):
        seq.setComponentByPosition(i, item)
    return seq


def _context_tag_bytes(tag_no: int) -> bytes:
    """context-constructed tag 编码（支持高 tag 号，如 [406]）。"""
    if tag_no < 31:
        return bytes([0xA0 | tag_no])
    out = [0xA0 | 0x1F]
    stack = []
    while tag_no > 0:
        stack.append(tag_no & 0x7F)
        tag_no >>= 7
    for i, b in enumerate(reversed(stack)):
        out.append(0x80 | b if i < len(stack) - 1 else b)
    return bytes(out)


def _encode_auth_list(*tagged_entries: tuple[int, bytes]) -> bytes:
    """手工构造 authorization list 的 DER 内容：若干 context-tagged TLV。"""
    out = b""
    for tag_no, content in tagged_entries:
        out += _context_tag_bytes(tag_no) + bytes([len(content)]) + content
    return out


def _encode_key_description(
    challenge: str, security_level: int, app_sig: str | None, extra_tee_tags=True
) -> bytes:
    """编码 KeyDescription（含 KeyDescription 外层 SEQUENCE 头）。"""
    from pyasn1.type import namedtype, tag, univ

    class _PackageInfo(univ.Sequence):
        componentType = namedtype.NamedTypes(
            namedtype.NamedType("packageName", univ.OctetString()),
            namedtype.NamedType("version", univ.Integer()),
        )

    class _AppId(univ.Sequence):
        componentType = namedtype.NamedTypes(
            namedtype.NamedType(
                "packageInfos", univ.SequenceOf(componentType=_PackageInfo())
            ),
            namedtype.NamedType(
                "signatureDigests", univ.SequenceOf(componentType=univ.OctetString())
            ),
        )

    def seq_of_octets(items):
        seq = univ.SequenceOf(componentType=univ.OctetString())
        for i, item in enumerate(items):
            seq.setComponentByPosition(i, item)
        return seq

    def build_app_id(digest_hex):
        # 注意：pyasn1 Sequence 的 **kwargs 构造会静默丢弃组件，
        # 必须用 __setitem__ 显式赋值
        app_id = _AppId()
        app_id["packageInfos"] = univ_seq([])
        app_id["signatureDigests"] = seq_of_octets([bytes.fromhex(digest_hex)])
        return app_id

    tee_entries: list[tuple[int, bytes]] = []
    if extra_tee_tags:
        # 真实链形态：数十个未知 context tag（purpose[1]/algorithm[2]/keySize[3]…）
        tee_entries.append((1, bytes([3])))  # purpose = sign
        tee_entries.append((2, bytes([3])))  # algorithm = EC
        tee_entries.append((3, bytes([1, 0])))  # keySize = 256
    if app_sig is not None:
        app_id_der = der_encode(build_app_id(app_sig))
        tee_entries.append((406, app_id_der))

    tee_content = _encode_auth_list(*tee_entries)
    software_content = _encode_auth_list()

    def tagged(no, content):
        return bytes([0xA0 | no, len(content)]) + content

    class _KeyDesc(univ.Sequence):
        componentType = namedtype.NamedTypes(
            namedtype.NamedType("attestationVersion", univ.Integer()),
            namedtype.NamedType("attestationSecurityLevel", univ.Enumerated()),
            namedtype.NamedType("keymasterVersion", univ.Integer()),
            namedtype.NamedType("keymasterSecurityLevel", univ.Enumerated()),
            namedtype.NamedType("attestationChallenge", univ.OctetString()),
            namedtype.NamedType("uniqueId", univ.OctetString()),
            namedtype.NamedType(
                "softwareEnforced",
                univ.OctetString().subtype(
                    implicitTag=tag.Tag(
                        tag.tagClassContext, tag.tagFormatConstructed, 0
                    )
                ),
            ),
            namedtype.NamedType(
                "teeEnforced",
                univ.OctetString().subtype(
                    implicitTag=tag.Tag(
                        tag.tagClassContext, tag.tagFormatConstructed, 1
                    )
                ),
            ),
        )

    key_desc = _KeyDesc()
    key_desc["attestationVersion"] = 3
    key_desc["attestationSecurityLevel"] = security_level
    key_desc["keymasterVersion"] = 1
    key_desc["keymasterSecurityLevel"] = security_level
    key_desc["attestationChallenge"] = challenge.encode()
    key_desc["uniqueId"] = b""
    key_desc["softwareEnforced"] = software_content
    key_desc["teeEnforced"] = tee_content
    return der_encode(key_desc, asn1Spec=_KeyDesc())


def _build_chain(
    challenge: str = CHALLENGE,
    security_level: int = 1,
    app_sig: str | None = APP_SIG_SHA256,
    extra_tee_tags: bool = True,
    trust_anchor: bool = True,
):
    """构造 [叶子(含attestation扩展), 根] 证书链与根指纹。"""
    root_key = _ec_key()
    leaf_key = _ec_key()
    root = _make_cert(root_key, root_key, "Test Root CA", "Test Root CA", ca=True)
    leaf = _make_cert(leaf_key, root_key, "Test Root CA", "Whimread Attestation Leaf")

    key_desc_der = _encode_key_description(
        challenge, security_level, app_sig, extra_tee_tags
    )
    leaf = (
        x509.CertificateBuilder()
        .subject_name(leaf.subject)
        .issuer_name(leaf.issuer)
        .public_key(leaf_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.now(UTC))
        .not_valid_after(datetime.now(UTC) + __import__("datetime").timedelta(days=365))
        .add_extension(
            x509.UnrecognizedExtension(ATTESTATION_OID, key_desc_der),
            critical=False,
        )
        .sign(root_key, hashes.SHA256())
    )

    root_fp = hashlib.sha256(root.fingerprint(hashes.SHA256())).hexdigest()
    if not trust_anchor:
        root_fp = "ff" * 32

    def pem(c):
        return c.public_bytes(serialization.Encoding.PEM).decode()

    return [pem(leaf), pem(root)], root_fp


@pytest.fixture(autouse=True)
def _trusted_root(monkeypatch):
    """默认信任根 = 测试自签根（每个用例的链不同，动态注册指纹）。"""
    fingerprints: set[str] = set()
    monkeypatch.setattr(att, "_load_trusted_root_fingerprints", lambda: fingerprints)
    return fingerprints


@pytest.fixture(autouse=True)
def _official_signature(monkeypatch):
    monkeypatch.setattr(settings, "expected_apk_signature_sha256", APP_SIG_SHA256)


class TestHappyPath:
    def test_真机形态_通过(self, _trusted_root):
        chain, root_fp = _build_chain()
        _trusted_root.add(root_fp)

        result = verify_key_attestation(chain, CHALLENGE)

        assert result.verified is True
        assert result.security_level == "TrustedEnvironment"
        assert len(result.leaf_public_key_sha256) > 0

    def test_带未知tag与无额外tag_均通过(self, _trusted_root):
        chain, root_fp = _build_chain(extra_tee_tags=False)
        _trusted_root.add(root_fp)
        result = verify_key_attestation(chain, CHALLENGE)
        assert result.verified is True

    def test_strongbox级_通过(self, _trusted_root):
        chain, root_fp = _build_chain(security_level=2)
        _trusted_root.add(root_fp)
        result = verify_key_attestation(chain, CHALLENGE)
        assert result.security_level == "StrongBox"


class TestRejections:
    def test_challenge不匹配_拒绝(self, _trusted_root):
        chain, root_fp = _build_chain()
        _trusted_root.add(root_fp)
        with pytest.raises(AuthenticationError) as exc:
            verify_key_attestation(chain, "wrong-challenge")
        assert exc.value.error_code == "ATTESTATION_CHALLENGE_MISMATCH"

    def test_software级_拒绝(self, _trusted_root):
        chain, root_fp = _build_chain(security_level=0)
        _trusted_root.add(root_fp)
        with pytest.raises(AuthenticationError) as exc:
            verify_key_attestation(chain, CHALLENGE)
        assert exc.value.error_code == "ATTESTATION_SOFTWARE_LEVEL"

    def test_签名摘要不匹配_拒绝(self, _trusted_root):
        chain, root_fp = _build_chain(app_sig="cd" * 32)
        _trusted_root.add(root_fp)
        with pytest.raises(AuthenticationError) as exc:
            verify_key_attestation(chain, CHALLENGE)
        assert exc.value.error_code == "ATTESTATION_SIGNATURE_MISMATCH"

    def test_非官方签名缺失_拒绝(self, _trusted_root):
        # 魔改包没有 attestationApplicationId → 摘要列表为空 → 拒绝
        chain, root_fp = _build_chain(app_sig=None)
        _trusted_root.add(root_fp)
        with pytest.raises(AuthenticationError) as exc:
            verify_key_attestation(chain, CHALLENGE)
        assert exc.value.error_code == "ATTESTATION_SIGNATURE_MISMATCH"

    def test_不可信根_拒绝(self, _trusted_root):
        chain, root_fp = _build_chain(trust_anchor=False)
        _trusted_root.add(root_fp)  # 注册的是错的指纹
        with pytest.raises(AuthenticationError) as exc:
            verify_key_attestation(chain, CHALLENGE)
        assert exc.value.error_code == "ATTESTATION_UNTRUSTED_ROOT"

    def test_单证书伪链_拒绝(self, _trusted_root):
        chain, _ = _build_chain()
        with pytest.raises(AuthenticationError) as exc:
            verify_key_attestation([chain[0]], CHALLENGE)
        assert exc.value.error_code == "ATTESTATION_CHAIN_INVALID"

    def test_空链_拒绝(self, _trusted_root):
        with pytest.raises(AuthenticationError) as exc:
            verify_key_attestation([], CHALLENGE)
        assert exc.value.error_code == "ATTESTATION_CHAIN_MISSING"

    def test_challenge不匹配优先于摘要检查(self, _trusted_root):
        # challenge 错 + 签名错的组合：challenge 检查先行
        chain, root_fp = _build_chain(app_sig="cd" * 32)
        _trusted_root.add(root_fp)
        with pytest.raises(AuthenticationError) as exc:
            verify_key_attestation(chain, "wrong-challenge")
        assert exc.value.error_code == "ATTESTATION_CHALLENGE_MISMATCH"
