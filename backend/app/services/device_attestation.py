#!/usr/bin/env python3
"""
Android Key Attestation 验证器。

校验设备上传的密钥证书链确系真实设备 TEE 为「我们下发的 challenge + 官方签名 APK」
生成，任何一环不满足即拒绝。校验项：

1. 证书链逐级签名验证，链尾必须锚定在可信根（默认 Google 硬件 attestation 根，
   指纹可经 ATTESTATION_ROOT_FINGERPRINTS 覆盖/扩展）
2. 叶子证书含 attestation 扩展（OID 1.3.6.1.4.1.11129.2.1.17）
3. attestationChallenge 与服务端下发的 nonce 一致（防重放）
4. attestationSecurityLevel = TrustedEnvironment(1) 或 StrongBox(2)——
   软件级(0)意味着密钥在系统内存中生成，模拟器/篡改环境可伪造，拒绝
5. attestationApplicationId.signatureDigests 包含官方 APK 签名证书摘要
   （魔改重签名包在此出局）

verify_key_attestation 为模块级函数，测试可 monkeypatch 注入假实现。
"""

import base64
import hashlib
import logging
from dataclasses import dataclass
from itertools import pairwise
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
from cryptography.x509 import UnrecognizedExtension
from pyasn1.codec.der.decoder import decode as der_decode
from pyasn1.error import PyAsn1Error
from pyasn1.type import namedtype, tag, univ

from ..config import settings
from ..exceptions import AuthenticationError

logger = logging.getLogger(__name__)

# Android Key Attestation 扩展 OID
ATTESTATION_EXTENSION_OID = "1.3.6.1.4.1.11129.2.1.17"

# attestationSecurityLevel 枚举
SECURITY_SOFTWARE = 0
SECURITY_TRUSTED_ENVIRONMENT = 1
SECURITY_STRONGBOX = 2

_SECURITY_LEVEL_NAMES = {0: "Software", 1: "TrustedEnvironment", 2: "StrongBox"}

# 默认信任根：Google 官方 hardware attestation root（app/services/attestation_roots/）
_DEFAULT_ROOT_PATH = (
    Path(__file__).parent / "attestation_roots" / "google_hardware_root.pem"
)
_DEFAULT_ROOT_FINGERPRINT = (
    "3c33d0bba390c2c67eda33cb15db9a1036f0aae75002c75b4ef9b248e5565e49"
)

# pyasn1 schema：KeyDescription（AuthorizationList 只解我们关心的 tag，其余 Any 跳过）


class _PackageInfo(univ.Sequence):
    componentType = namedtype.NamedTypes(
        namedtype.NamedType("packageName", univ.OctetString()),
        namedtype.NamedType("version", univ.Integer()),
    )


class _AttestationApplicationId(univ.Sequence):
    componentType = namedtype.NamedTypes(
        namedtype.NamedType(
            "packageInfos", univ.SequenceOf(componentType=_PackageInfo())
        ),
        namedtype.NamedType(
            "signatureDigests", univ.SequenceOf(componentType=univ.OctetString())
        ),
    )


class _AuthorizationList(univ.Sequence):
    """context-tagged 授权项；仅 406 (attestationApplicationId) 关心内容。"""

    componentType = namedtype.NamedTypes(
        namedtype.OptionalNamedType(
            "attestationApplicationId",
            univ.Sequence().subtype(
                implicitTag=tag.Tag(tag.tagClassContext, tag.tagFormatConstructed, 406)
            ),
        ),
    )


class _KeyDescription(univ.Sequence):
    componentType = namedtype.NamedTypes(
        namedtype.NamedType("attestationVersion", univ.Integer()),
        namedtype.NamedType("attestationSecurityLevel", univ.Enumerated()),
        namedtype.NamedType("keymasterVersion", univ.Integer()),
        namedtype.NamedType("keymasterSecurityLevel", univ.Enumerated()),
        namedtype.NamedType("attestationChallenge", univ.OctetString()),
        namedtype.NamedType("uniqueId", univ.OctetString()),
        namedtype.NamedType("softwareEnforced", _AuthorizationList()),
        namedtype.NamedType("teeEnforced", _AuthorizationList()),
    )


@dataclass
class AttestationResult:
    security_level: str
    verified: bool
    leaf_public_key_sha256: str


def _load_trusted_root_fingerprints() -> set[str]:
    """可信根指纹集合：默认 Google 根 + 环境变量扩展（逗号分隔 hex）。"""
    fingerprints = {_DEFAULT_ROOT_FINGERPRINT}
    extra = getattr(settings, "attestation_root_fingerprints", "") or ""
    for fp in extra.split(","):
        fp = fp.strip().lower().replace(":", "")
        if fp:
            fingerprints.add(fp)
    return fingerprints


def _cert_fingerprint_sha256(cert: x509.Certificate) -> str:
    return hashlib.sha256(cert.fingerprint(hashes.SHA256())).hexdigest()


def _verify_chain(chain: list[x509.Certificate]) -> x509.Certificate:
    """逐级验证签名，返回根证书；结构/签名/信任根任一失败即抛错。"""
    if len(chain) < 2:
        raise AuthenticationError(
            "证书链不完整", error_code="ATTESTATION_CHAIN_INVALID"
        )
    for cert, issuer in pairwise(chain):
        try:
            cert.verify_directly_issued_by(issuer)
        except (ValueError, TypeError) as e:
            raise AuthenticationError(
                "证书链签名验证失败", error_code="ATTESTATION_CHAIN_INVALID"
            ) from e
    root = chain[-1]
    root_fp = _cert_fingerprint_sha256(root)
    if root_fp not in _load_trusted_root_fingerprints():
        logger.warning("Attestation chain terminated at untrusted root: %s", root_fp)
        raise AuthenticationError(
            "证书链未锚定到可信根", error_code="ATTESTATION_UNTRUSTED_ROOT"
        )
    return root


def _parse_key_description(leaf: x509.Certificate) -> tuple[univ.Sequence, int]:
    """解析叶子证书的 attestation 扩展，返回 (KeyDescription, securityLevel)。"""
    try:
        ext = leaf.extensions.get_extension_for_oid(
            x509.ObjectIdentifier(ATTESTATION_EXTENSION_OID)
        )
    except x509.ExtensionNotFound as e:
        raise AuthenticationError(
            "叶子证书缺少 attestation 扩展", error_code="ATTESTATION_EXTENSION_MISSING"
        ) from e

    raw_ext = ext.value
    raw_der = raw_ext.value if isinstance(raw_ext, UnrecognizedExtension) else None
    if raw_der is None:
        raise AuthenticationError(
            "attestation 扩展格式不受支持", error_code="ATTESTATION_MALFORMED"
        )
    try:
        obj, _ = der_decode(raw_der, asn1Spec=_KeyDescription())
    except PyAsn1Error as e:
        raise AuthenticationError(
            "attestation 扩展解析失败", error_code="ATTESTATION_MALFORMED"
        ) from e

    security_level = int(obj["attestationSecurityLevel"])
    return obj, security_level


def verify_key_attestation(
    certificate_chain_pem: list[str],
    expected_challenge: str,
) -> AttestationResult:
    """验证 attestation 证书链；全部通过返回结果，任何失败抛 AuthenticationError。

    Args:
        certificate_chain_pem: 顺序为 [叶子, ..., 根] 的 PEM 证书列表
        expected_challenge: 服务端此前下发的 nonce
    """
    if not certificate_chain_pem:
        raise AuthenticationError(
            "缺少 attestation 证书链", error_code="ATTESTATION_CHAIN_MISSING"
        )
    try:
        chain = [
            x509.load_pem_x509_certificate(
                pem.encode() if isinstance(pem, str) else pem
            )
            for pem in certificate_chain_pem
        ]
    except ValueError as e:
        raise AuthenticationError(
            "证书 PEM 解析失败", error_code="ATTESTATION_MALFORMED"
        ) from e

    _verify_chain(chain)
    leaf = chain[0]

    key_desc, security_level = _parse_key_description(leaf)

    # challenge 匹配（防重放：nonce 一次性，60 秒过期）
    challenge = str(key_desc["attestationChallenge"])
    if challenge != expected_challenge:
        raise AuthenticationError(
            "attestation challenge 不匹配", error_code="ATTESTATION_CHALLENGE_MISMATCH"
        )

    # 硬件级安全要求
    if security_level not in (SECURITY_TRUSTED_ENVIRONMENT, SECURITY_STRONGBOX):
        raise AuthenticationError(
            "密钥非硬件安全区生成（Software attestation 不接受）",
            error_code="ATTESTATION_SOFTWARE_LEVEL",
        )

    # 官方 APK 签名摘要匹配（魔改包出局）
    expected_sig = (settings.expected_apk_signature_sha256 or "").strip().lower()
    if expected_sig:
        app_id = None
        for field_name in ("teeEnforced", "softwareEnforced"):
            auth_list = key_desc[field_name]
            if "attestationApplicationId" in auth_list:
                app_id = auth_list["attestationApplicationId"]
                break
        digests: list[str] = []
        if app_id is not None:
            try:
                app_id_obj, _ = der_decode(
                    bytes(app_id), asn1Spec=_AttestationApplicationId()
                )
                digests = [bytes(d).hex() for d in app_id_obj["signatureDigests"]]
            except PyAsn1Error as e:
                raise AuthenticationError(
                    "attestationApplicationId 解析失败",
                    error_code="ATTESTATION_MALFORMED",
                ) from e
        if expected_sig not in digests:
            logger.warning(
                "APK signature digest mismatch: expected %s, attested %s",
                expected_sig[:12],
                [d[:12] for d in digests] or "none",
            )
            raise AuthenticationError(
                "APK 签名与官方发行版不符", error_code="ATTESTATION_SIGNATURE_MISMATCH"
            )

    leaf_pub = leaf.public_key()
    # SPKI DER 编码对 RSA/EC 密钥统一适用，用于公钥指纹
    leaf_pub_sha256 = base64.b64encode(
        hashlib.sha256(
            leaf_pub.public_bytes(
                encoding=Encoding.DER, format=PublicFormat.SubjectPublicKeyInfo
            )
        ).digest()
    ).decode()

    return AttestationResult(
        security_level=_SECURITY_LEVEL_NAMES.get(security_level, "Unknown"),
        verified=True,
        leaf_public_key_sha256=leaf_pub_sha256,
    )
