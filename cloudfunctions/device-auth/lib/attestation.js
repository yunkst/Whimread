/**
 * Android Key Attestation 证书链验证(占位实现)
 *
 * 生产环境应接:
 *   1. 腾讯云 KMS VerifyAttestation 接口,或
 *   2. 自己实现 Google 证书链验证(根证书 hard-code)
 *
 * 本轮只做"格式校验 + 非空判断",返回 trusted: boolean。
 * trusted=false 时 device-auth 仍允许注册(给额度 0,标记 unverified),
 * trusted=true 时给完整 100 额度。
 */

const BEGIN_CERT = '-----BEGIN CERTIFICATE-----';

/**
 * 验证 attestation 证书链
 *
 * @param {string[]} chain PEM 格式证书链数组
 * @param {string} challenge 之前下发的 challenge nonce
 * @returns {{trusted: boolean, reason: string, leafCert: string|null}}
 */
function verifyAttestation(chain, challenge) {
    if (!Array.isArray(chain) || chain.length === 0) {
        return { trusted: false, reason: 'EMPTY_CHAIN', leafCert: null };
    }
    const leaf = chain[0];
    if (typeof leaf !== 'string' || !leaf.includes(BEGIN_CERT)) {
        return { trusted: false, reason: 'INVALID_PEM', leafCert: null };
    }

    // 占位:信任任何含 BEGIN CERTIFICATE 的非空链
    // 生产应在此处:
    //   - 用 KMS VerifyAttestation 校验 chain 的根证书是 Google Hardware Attestation Root
    //   - 从 leaf cert 提取 attestationChallenge 字段,对比 === challenge
    //   - 检查 TEE 等级(Trusted Execution Environment attestation level >= TEE)
    return {
        trusted: true,
        reason: 'PLACEHOLDER_OK',
        leafCert: leaf,
    };
}

module.exports = { verifyAttestation };
