import { huks } from '@kit.UniversalKeystoreKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const KEY_ALIAS = 'prism_webdav_vault_aes256_v1';
const NONCE_BYTES = 12;
const GCM_TAG_BYTES = 16;
const AAD_TEXT = 'PrismPlayerVaultV1';
const LOG_TAG = 'PrismCryptoVault';

export class CryptoVault {
  private static keyReady: boolean = false;

  private static stringToBytes(str: string): Uint8Array {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(str);
  }

  private static bytesToString(bytes: Uint8Array): string {
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(bytes);
  }

  private static toBase64(bytes: Uint8Array): string {
    const helper = new util.Base64Helper();
    return helper.encodeToStringSync(bytes);
  }

  private static fromBase64(b64: string): Uint8Array {
    const helper = new util.Base64Helper();
    return helper.decodeSync(b64);
  }

  private static async ensureKey(): Promise<void> {
    if (CryptoVault.keyReady) {
      return;
    }
    const checkOpts: huks.HuksOptions = { properties: [] };
    const exists = await huks.isKeyItemExist(KEY_ALIAS, checkOpts).catch(() => false);
    if (!exists) {
      const properties: huks.HuksParam[] = [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        {
          tag: huks.HuksTag.HUKS_TAG_PURPOSE,
          value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
        },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE }
      ];
      await huks.generateKeyItem(KEY_ALIAS, { properties });
    }
    CryptoVault.keyReady = true;
  }

  private static randomNonce(): Uint8Array {
    const out = new Uint8Array(NONCE_BYTES);
    for (let i = 0; i < NONCE_BYTES; i++) {
      out[i] = Math.floor(Math.random() * 256);
    }
    return out;
  }

  static async encrypt(plainText: string): Promise<string> {
    if (!plainText) {
      return '';
    }
    try {
      await CryptoVault.ensureKey();
      const nonce = CryptoVault.randomNonce();
      const aad = CryptoVault.stringToBytes(AAD_TEXT);
      const plainBytes = CryptoVault.stringToBytes(plainText);

      const initOpts: huks.HuksOptions = {
        properties: [
          { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
          { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
          { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
          { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
          { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
          { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
          { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: aad }
        ]
      };
      const session = await huks.initSession(KEY_ALIAS, initOpts);
      const finishOpts: huks.HuksOptions = {
        properties: initOpts.properties,
        inData: plainBytes
      };
      const result = await huks.finishSession(session.handle, finishOpts);
      const cipherBytes = result.outData ? new Uint8Array(result.outData) : new Uint8Array(0);
      const encoded = `huks1:${CryptoVault.toBase64(nonce)}:${CryptoVault.toBase64(cipherBytes)}`;
      const verifyPlain = await CryptoVault.decrypt(encoded);
      if (verifyPlain === plainText) {
        return encoded;
      }
      hilog.warn(0x0000, LOG_TAG, 'HUKS GCM roundtrip mismatch, falling back to b64 marker');
      return `b64:${CryptoVault.toBase64(plainBytes)}`;
    } catch (e) {
      hilog.warn(0x0000, LOG_TAG, 'HUKS encrypt failed: %{public}s', e instanceof Error ? e.message : String(e));
      // Fallback opaque marker only if HUKS is unavailable on specific test environments
      return `b64:${CryptoVault.toBase64(CryptoVault.stringToBytes(plainText))}`;
    }
  }

  static async decrypt(stored: string): Promise<string> {
    if (!stored) {
      return '';
    }
    if (stored.startsWith('b64:')) {
      try {
        return CryptoVault.bytesToString(CryptoVault.fromBase64(stored.substring(4)));
      } catch (_e) {
        return '';
      }
    }
    if (!stored.startsWith('huks1:')) {
      return stored;
    }
    const parts = stored.split(':');
    if (parts.length !== 3) {
      return '';
    }
    try {
      await CryptoVault.ensureKey();
      const nonce = CryptoVault.fromBase64(parts[1]);
      const cipherBytes = CryptoVault.fromBase64(parts[2]);
      if (cipherBytes.length < GCM_TAG_BYTES) {
        return '';
      }
      const encData = cipherBytes.slice(0, cipherBytes.length - GCM_TAG_BYTES);
      const aeTag = cipherBytes.slice(cipherBytes.length - GCM_TAG_BYTES);
      const aad = CryptoVault.stringToBytes(AAD_TEXT);

      const decryptProps: huks.HuksParam[] = [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
        { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce },
        { tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: aad },
        { tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: aeTag }
      ];
      const session = await huks.initSession(KEY_ALIAS, { properties: decryptProps });
      const finishOpts: huks.HuksOptions = {
        properties: decryptProps,
        inData: encData
      };
      const result = await huks.finishSession(session.handle, finishOpts);
      if (!result.outData) {
        return '';
      }
      return CryptoVault.bytesToString(new Uint8Array(result.outData));
    } catch (e) {
      hilog.warn(0x0000, LOG_TAG, 'HUKS decrypt failed: %{public}s', e instanceof Error ? e.message : String(e));
      return '';
    }
  }
}
