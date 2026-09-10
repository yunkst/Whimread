package com.example.novel_app

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.cert.Certificate
import java.security.spec.ECGenParameterSpec

/**
 * 设备注册通道：Android Key Attestation + 请求签名。
 *
 * 安全模型：
 * - 私钥生成于硬件 TEE（setAttestationChallenge 传入的 challenge 会被写进
 *   attestation 证书），不可导出——额度账户绑死在设备上。
 * - [signChallenge] 用该私钥对服务端下发的 nonce 做 SHA256withECDSA 签名，
 *   服务端用注册时登记的公钥验签，即可确认"还是原来那台设备"。
 */
object DeviceAttestation {

    private const val KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "whimread_device_key"
    private const val EC_CURVE = "secp256r1"

    /**
     * 生成（或复用）硬件密钥并返回证书链（PEM 列表，[叶子, ..., 根]）。
     *
     * @param challenge 服务端下发的 nonce，会被写入 attestation 证书扩展
     */
    fun attest(call: MethodCall, result: MethodChannel.Result, context: Context) {
        val challenge = call.argument<String>("challenge")
        if (challenge.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "challenge is required", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            result.error("UNSUPPORTED", "Key Attestation requires Android 6.0+", null)
            return
        }
        try {
            val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }

            // challenge 是一次性 nonce：每次 attest 都必须重新生成密钥，
            // 让新 challenge 写入新的 attestation 证书（旧证书对服务端已无效）
            generateAttestedKey(challenge)

            val chain = keyStore.getCertificateChain(KEY_ALIAS)
                ?: throw IllegalStateException("key generation produced no certificate chain")
            val pemList = chain.filterNotNull().map { toPem(it) }
            result.success(pemList)
        } catch (e: Exception) {
            result.error("ATTESTATION_FAILED", e.message ?: "attestation failed", null)
        }
    }

    /** 用 TEE 私钥对服务端 nonce 做 SHA256withECDSA 签名（Base64）。 */
    fun signChallenge(call: MethodCall, result: MethodChannel.Result) {
        val nonce = call.argument<String>("nonce")
        if (nonce.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "nonce is required", null)
            return
        }
        try {
            val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            val entry = keyStore.getEntry(KEY_ALIAS, null)
                as? KeyStore.PrivateKeyEntry
                ?: run {
                    result.error("NO_KEY", "device key not registered yet", null)
                    return
                }
            val signature = Signature.getInstance("SHA256withECDSA").apply {
                initSign(entry.privateKey)
                update(nonce.toByteArray(Charsets.UTF_8))
            }
            val sig = signature.sign()
            // ECDSA 签名是 DER 编码的 r|s；转成 JWT 风格的 raw r|s（64 字节），
            // 服务端用 cryptography 的 EC 算法验签时两种都认，这里保持 DER + Base64 即可
            result.success(Base64.encodeToString(sig, Base64.NO_WRAP))
        } catch (e: Exception) {
            result.error("SIGN_FAILED", e.message ?: "sign failed", null)
        }
    }

    fun hasKey(): Boolean {
        return try {
            val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            keyStore.containsAlias(KEY_ALIAS)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 读取 [Settings.Secure.ANDROID_ID]（真正的 SSAID，按 APP 签名 + 用户隔离）。
     *
     * 为什么不用 device_info_plus 的 AndroidDeviceInfo.id：那个字段实际是
     * [Build.ID]（如 `BP2A.250605.031.A3_V000L1`），同型号同系统版本的所有设备
     * 共享同一字符串，无法作为设备唯一标识；用它注册会让第二台同款机继承第一台
     * 的账户/额度。Settings.Secure.ANDROID_ID 自 Android 8 起对每个 (signing key,
     * user) 组合稳定，是 Google 官方推荐的设备唯一标识，无需任何运行时权限。
     *
     * 返回 null 表示系统未提供（极旧版本或被 OEM 屏蔽），由 Dart 侧 fallback。
     */
    fun getAndroidId(context: Context): String? {
        return try {
            Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
                ?.takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            null
        }
    }

    private fun generateAttestedKey(challenge: String) {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        if (keyStore.containsAlias(KEY_ALIAS)) {
            keyStore.deleteEntry(KEY_ALIAS)
        }

        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC, KEYSTORE
        )
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY
        )
            .setAlgorithmParameterSpec(ECGenParameterSpec(EC_CURVE))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setAttestationChallenge(challenge.toByteArray(Charsets.UTF_8))
            .build()
        generator.initialize(spec)
        generator.generateKeyPair()
    }

    private fun toPem(cert: Certificate): String {
        val encoded = Base64.encodeToString(cert.encoded, Base64.NO_WRAP)
        return buildString {
            append("-----BEGIN CERTIFICATE-----\n")
            encoded.chunked(64).forEach { append(it).append('\n') }
            append("-----END CERTIFICATE-----")
        }
    }
}
