'use strict';
// リトライとタイムアウトの判断だけを置く。通信と出力は client.js が行う。

// 再試行の対象は、5xx のうち 500 と 503、および 429。502 と 504 は対象外。
function classify(status) {
  if (status === 500 || status === 503) return '5xx';
  if (status === 429) return '429';
  return null;
}

// 倍々にしながら、上限で止める。基準が 0 なら待たない。
function backoff5xx(retryNumber, baseSeconds, capSeconds) {
  if (baseSeconds === 0) return 0;
  return Math.min(baseSeconds * 2 ** (retryNumber - 1), capSeconds);
}

// Retry-After の秒数を取り出す。数字だけの値を受け付け、それ以外（日付、負数、小数）は無いものとして扱う。
// 7 桁以上の数字は、上限超過として 1000000 に丸める。
function parseRetryAfter(value) {
  if (typeof value !== 'string') return null;
  const v = value.trim();
  if (!/^\d+$/.test(v)) return null;
  return v.length > 6 ? 1000000 : Number(v);
}

// 429 の待機秒数と、上限で切り詰めたかどうか。Retry-After が無ければ既定の待機秒数を使う。
function wait429(retryAfterSeconds, defaultSeconds, capSeconds) {
  const wanted = retryAfterSeconds === null ? defaultSeconds : retryAfterSeconds;
  return wanted > capSeconds ? { seconds: capSeconds, capped: 1 } : { seconds: wanted, capped: 0 };
}

const DEFAULTS = {
  RETRY_MAX_ATTEMPTS_5XX: [3, 0],
  RETRY_BACKOFF_BASE_SECONDS: [1, 0],
  RETRY_MAX_ATTEMPTS_429: [3, 0],
  RETRY_429_DEFAULT_WAIT_SECONDS: [2, 0],
  RETRY_MAX_WAIT_SECONDS: [30, 0],
  CONNECT_TIMEOUT_SECONDS: [5, 1],
  RESPONSE_TIMEOUT_SECONDS: [10, 1],
};

// 環境変数から設定を読む。未設定は既定値。整数でない値や最小値未満は、その名前を返して止める。
function loadConfig(env) {
  const config = {};
  for (const [name, [fallback, min]] of Object.entries(DEFAULTS)) {
    const raw = env[name];
    if (raw === undefined || raw === '') {
      config[name] = fallback;
      continue;
    }
    if (!/^\d{1,6}$/.test(raw) || Number(raw) < min) return { invalid: name };
    config[name] = Number(raw);
  }
  return { config };
}

module.exports = { classify, backoff5xx, parseRetryAfter, wait429, loadConfig };
