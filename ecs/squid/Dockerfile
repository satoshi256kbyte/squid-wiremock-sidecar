# Squid の派生イメージ。
# squid.conf は1つだけ持ち、起動時に環境変数で書き換えて、転送先を WireMock と外部 API で切り替える。
# 環境ごとの設定ファイルは持たない。ボリュームにも頼らない。
FROM ubuntu/squid:latest
# 書き換え前の設定。起動時に、環境変数に合わせて /etc/squid/squid.conf に書き換える
COPY squid.conf /etc/squid/squid.conf.src
# 許可するドメインの一覧。squid.conf の acl が読む
COPY whitelist.txt /etc/squid/whitelist.txt
# squid.conf を書き換えるスクリプトと、それを呼ぶ起動スクリプト
COPY derive-config.sh /usr/local/bin/swsc-derive-config.sh
COPY entrypoint.sh /usr/local/bin/swsc-entrypoint.sh
RUN chmod 0755 /usr/local/bin/swsc-derive-config.sh /usr/local/bin/swsc-entrypoint.sh
# ここで呼ばれるスクリプトの中で、Squid の設定ファイルを書き換える
ENTRYPOINT ["/usr/local/bin/swsc-entrypoint.sh"]
