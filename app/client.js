'use strict';
// 外部 API を呼ぶクライアントアプリ。HTTP プロキシ（HTTP_PROXY）経由で GET し、
// 5xx と 429 は再試行し、応答が遅いときはタイムアウトで終わる。依存パッケージは使わない。
// 結果は、標準出力に CLIENT_STATUS と CLIENT_BODY、標準エラーに CLIENT_DIAG の行で出す。
const http = require('node:http');
const https = require('node:https');
const tls = require('node:tls');
const { classify, backoff5xx, parseRetryAfter, wait429, loadConfig } = require('./retry');

const EXIT_CONFIG = 78;
const EXIT_TIMEOUT = 28;

const out = (line) => process.stdout.write(`${line}\n`);
const err = (line) => process.stderr.write(`${line}\n`);
const sleep = (seconds) => new Promise((resolve) => setTimeout(resolve, seconds * 1000));

// プロキシ経由で GET する。接続の待ちと応答の待ちに、それぞれ時間制限を付ける。
// http:// の宛先は、絶対 URL をプロキシへ送る。https:// の宛先は、CONNECT でトンネルを作ってから TLS で話す。
function request(proxy, target, config) {
  return new Promise((resolve, reject) => {
    let done = false;
    let current = null;
    const finish = (fn, value) => {
      if (done) return;
      done = true;
      clearTimeout(connectTimer);
      clearTimeout(totalTimer);
      fn(value);
    };
    const fail = (e) => {
      if (current) current.destroy();
      finish(reject, e);
    };
    const timeout = () => {
      const e = new Error('timeout');
      e.code = 'TIMEOUT';
      fail(e);
    };
    const connectTimer = setTimeout(timeout, config.CONNECT_TIMEOUT_SECONDS * 1000);
    const totalTimer = setTimeout(timeout, config.RESPONSE_TIMEOUT_SECONDS * 1000);

    const onResponse = (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => finish(resolve, { status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString('utf8') }));
      res.on('error', fail);
    };
    // 接続は使い回さず、応答の後に閉じる。開いたままだと、プロセスが数秒終わらない。
    const headers = { Host: target.host, Connection: 'close' };

    if (target.protocol === 'https:') {
      const port = target.port || '443';
      const connect = http.request({ host: proxy.hostname, port: proxy.port, method: 'CONNECT', path: `${target.hostname}:${port}`, agent: false });
      current = connect;
      connect.on('error', fail);
      connect.on('connect', (res, socket) => {
        clearTimeout(connectTimer);
        if (res.statusCode !== 200) {
          socket.destroy();
          const e = new Error(`proxy CONNECT ${res.statusCode}`);
          e.code = `PROXY_CONNECT_${res.statusCode}`;
          fail(e);
          return;
        }
        const req = https.request(
          { createConnection: () => tls.connect({ socket, servername: target.hostname }), method: 'GET', host: target.hostname, path: `${target.pathname}${target.search}`, agent: false, headers },
          onResponse,
        );
        current = req;
        req.on('error', fail);
        req.end();
      });
      connect.end();
      return;
    }

    const req = http.request({ host: proxy.hostname, port: proxy.port, method: 'GET', path: target.href, agent: false, headers }, onResponse);
    current = req;
    req.on('socket', (socket) => socket.once('connect', () => clearTimeout(connectTimer)));
    req.on('error', fail);
    req.end();
  });
}

async function main(env) {
  if (!env.HTTP_PROXY) {
    err('CLIENT_ERROR=proxy_not_configured');
    return EXIT_CONFIG;
  }
  const loaded = loadConfig(env);
  if (loaded.invalid) {
    err('CLIENT_ERROR=invalid_config');
    err(`CLIENT_DIAG invalid_config name=${loaded.invalid}`);
    return EXIT_CONFIG;
  }
  const config = loaded.config;
  const proxy = new URL(env.HTTP_PROXY);
  const base = env.TEST_API_BASE_URL || 'http://api.example.com';
  const target = new URL((env.TEST_API_PATH || '/api/users/123').replace(/^\/+/, '/'), base);

  let attempt = 0;
  let retries5xx = 0;
  let retries429 = 0;
  for (;;) {
    attempt += 1;
    let res;
    try {
      res = await request(proxy, target, config);
    } catch (e) {
      if (e.code === 'TIMEOUT') {
        // タイムアウトは再試行しない。接続が遅いのか応答が遅いのかは区別しない。
        err('CLIENT_ERROR=timeout');
        err(`CLIENT_DIAG result=timeout attempts=${attempt}`);
        return EXIT_TIMEOUT;
      }
      err('CLIENT_ERROR=network_error');
      err(`CLIENT_DIAG network_error attempts=${attempt} code=${e.code || 'unknown'}`);
      return 1;
    }

    const finish = (result) => {
      out(`CLIENT_STATUS=${res.status}`);
      out(`CLIENT_BODY=${res.body.replace(/\s+/g, ' ')}`);
      err(`CLIENT_DIAG result=${result} attempts=${attempt} status=${res.status}`);
      return 0;
    };

    const kind = classify(res.status);
    if (kind === null) return finish('success');

    // 5xx と 429 は、独立した回数で数える。片方の失敗が、もう片方の回数を使い切らないため。
    if (kind === '5xx') {
      if (retries5xx >= config.RETRY_MAX_ATTEMPTS_5XX) return finish('retries_exhausted');
      retries5xx += 1;
      const delay = backoff5xx(retries5xx, config.RETRY_BACKOFF_BASE_SECONDS, config.RETRY_MAX_WAIT_SECONDS);
      err(`CLIENT_DIAG retry attempt=${attempt} status=${res.status} class=5xx retry=${retries5xx}/${config.RETRY_MAX_ATTEMPTS_5XX} wait=${delay}`);
      await sleep(delay);
      continue;
    }

    if (retries429 >= config.RETRY_MAX_ATTEMPTS_429) return finish('retries_exhausted');
    retries429 += 1;
    const retryAfter = parseRetryAfter(res.headers['retry-after']);
    const waited = wait429(retryAfter, config.RETRY_429_DEFAULT_WAIT_SECONDS, config.RETRY_MAX_WAIT_SECONDS);
    err(`CLIENT_DIAG retry attempt=${attempt} status=${res.status} class=429 retry=${retries429}/${config.RETRY_MAX_ATTEMPTS_429} retry_after=${retryAfter === null ? 'none' : retryAfter} wait=${waited.seconds} capped=${waited.capped}`);
    await sleep(waited.seconds);
  }
}

main(process.env).then((code) => {
  process.exitCode = code;
});
