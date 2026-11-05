# Squid の派生イメージ（M09 FR-908、G5）。
# Why: 既存の squid.conf を単一の情報源にし、起動時に上流だけを派生させる。ボリュームに頼らない。
FROM ubuntu/squid:latest
COPY squid.conf /etc/squid/squid.conf.src
COPY whitelist.txt /etc/squid/whitelist.txt
COPY derive-config.sh /usr/local/bin/swsc-derive-config.sh
COPY entrypoint.sh /usr/local/bin/swsc-entrypoint.sh
RUN chmod 0755 /usr/local/bin/swsc-derive-config.sh /usr/local/bin/swsc-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/swsc-entrypoint.sh"]
