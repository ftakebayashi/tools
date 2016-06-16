#!/bin/bash

# プロセス監視用（変更不可）
processName="inotifywait"

# デプロイ用ファイルアップロード先パスを設定（FTPのカレント）
srcFilePath="/path/to/dir"

# 展開先のパスを設定（nginxで静的ファイル用に設定されているディレクトリ）
destFilePath="/path/to/dir"

# 展開先サーバーの設定（複数設定可。各サーバーにsshでログイン可能にしておく）
destServers=("sshuser@remotehost:")

# 展開開始用ファイルアップロード先設定
triggerFilePath="/path/to/dir"

# バックアップ作成先ディレクトリ設定
backupPath="/path/to/dir"
newBackupPath=${backupPath}/`date "+%Y%m%d"`/

# 展開開始用ファイル名設定
triggerFileName="deploy"

# ssh_keyパス設定
sshKeyPath="/path/to/ssh_key"


# バックアップをとる
backup () {

    # 3日以前のバックアップは削除 
    find $backupPath -mtime +2 -type d | xargs rm -rf

    currentFileName=`date "+%Y%m%d"`

    # 同じ日付のディレクトリを走査
    files=`ls -dt ${backupPath}/${currentFileName}*`

    # 同じ日付のディレクトリ数
    filesArray=($files)
    i=${#filesArray[*]}

    # 同じ日に作られているバックアップがある場合は、末尾をインクリメントして移動
    for same in $filesArray; do
        mv ${same} ${backupPath}/${currentFileName}_${i}
        i=$(( i - 1 ))
    done

    # 過去のバックアップの最新を取得
    for newest in `ls -dt $backupPath/*`; do
        break
    done

    # 最新のバックアップとの差分を新規バックアップに保存（更新されていないファイルはハードリンク）
    rsync -va --link-dest=$newest $srcFilePath $newBackupPath

}

# ファイルを同期する
deploy () {
    # scpで転送する場合はこの様にする
    #（削除したファイルが反映できない。転送先パスの指定が一つ上の階層になるので注意）
    #scp -i $sshKeyPath -r $srcFilePath ${e}:$destFilePath

    # rsyncで転送する場合はこの様にする
    for e in ${destServers[@]}; do
        rsync -r -e "ssh -i $sshKeyPath" --delete $srcFilePath ${e}$destFilePath
        echo "server deploy ${e}"
    done
    rm -f $triggerFilePath/$triggerFileName 
}

normal () {
    # ディレクトリ監視
    while read -r f; do
        if [ $f = $triggerFileName ] ; then
            backup
            deploy
        fi
    done < <(inotifywait --format '%f' -e create -m $triggerFilePath)
}

immidiate() {
    backup
    deploy
}

# 重複プロセスの監視
isAlive=`ps -ef | grep "$processName" | grep -v grep | grep -v srvchk | wc -l`
if [ $isAlive = 1 ]; then
    echo "Already started."
    exit
fi

if [ ! -z "$1" ] && [ $1 = 'now' ]; then
    # 即時実行
    immidiate
else
    # 終了時にinotifywaitも終了させる
    trap 'pgrep -f inotifywait | xargs kill' EXIT
    # 監視実行
    normal
fi
