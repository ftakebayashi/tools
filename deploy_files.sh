#!/bin/bash
# 特定のディレクトリに指定ファイル名のファイルが作成された時に
# 他サーバーにファイルをばらまくスクリプト
# Ctrl+Cで終了できます。
# 
# inotify-tools 要インストール

# プロセス監視用（変更不可）
processName="inotifywait"

# デプロイ用ファイルアップロード先パスを設定
deployFilePath="/path/to/src/"

# 展開先のパスを設定
targetFilePath="/path/to/dest/"

# 展開先サーバーの設定（複数設定可。各サーバーにsshでログイン可能にしておく）
targetServers=("sshuser@192.168.XX.XX" "sshuser@192.168.YY.YY")

# 展開開始用ファイルアップロード先設定
triggerFilePath="/path/to/trigger/"

# 展開開始用ファイル名設定
triggerFileName="deploy"

# ssh_keyパス設定
sshKeyPath="/path/to/id_rsa"

# 重複プロセスの監視
isAlive=`ps -ef | grep "$processName" | grep -v grep | grep -v srvchk | wc -l`
if [ $isAlive = 1 ]; then
    echo "Already started."
    exit
fi

# 強制終了時にinotifywaitも終了させる
trap 'pgrep -f inotifywait | xargs kill' EXIT

# ディレクトリ監視
while read -r f; do
    if [ $f = $triggerFileName ] ; then

        # scpで転送する場合はこの様にする
        #（削除したファイルが反映できない。転送先パスの指定が一つ上の階層になるので注意）
        #scp -i $sshKeyPath -r $deployFilePath ${e}:$targetFilePath

        # rsyncで転送する場合はこの様にする
        i=0
        for e in ${targetServers[@]}; do
            rsync -r -e "ssh -i $sshKeyPath" --delete $deployFilePath ${e}:$targetFilePath
            echo "server deploy ${e}"
            let i++
        done
        rm -f $triggerFilePath$triggerFileName 
    fi
done < <(inotifywait --format '%f' -e create -m $triggerFilePath)


