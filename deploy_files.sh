#!/bin/bash

# *********************************************************************
# プロセス監視用（変更不可）
processName="inotifywait"

# 展開開始用ファイル名設定
triggerFileName="deploy"
restoreFileName="restore"
# *********************************************************************

# デプロイ用ファイルアップロード先パスを設定（FTPのカレント）
srcFilePath=""

# 展開先のパスを設定（nginxで静的ファイル用に設定されているディレクトリ）
destFilePath=""

# 展開先サーバーの設定（複数設定可。各サーバーにsshでログイン可能にしておく）
destServers=("" "")

# 展開開始用ファイルアップロード先設定
triggerFilePath=""

# バックアップ作成先ディレクトリ設定
backupPath=""
newBackupPath=${backupPath}/`date "+%Y%m%d"`/

# ssh_keyパス設定
sshKeyPath=""


# バックアップをとる
backup () {

    echo "`date "+%Y/%m/%d %H:%M:%S"`********** BEGIN Backup "

    # 3日以前のバックアップは削除 
    find $backupPath -maxdepth 1 -mtime +2 -type d | xargs rm -rf

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
    rsync -a --link-dest=$newest $destFilePath/ $newBackupPath

    echo "`date "+%Y/%m/%d %H:%M:%S"`********** END   Backup "
    echo ""
}

# ファイルを同期する
deploy () {

    echo "`date "+%Y/%m/%d %H:%M:%S"`********** BEGIN Deploy "

    for e in ${destServers[@]}; do
        echo "`date "+%Y/%m/%d %H:%M:%S"`***** BEGIN ${e} Deploy *****"
        rsync -v -r -e "ssh -i $sshKeyPath" --delete $srcFilePath/ ${e}$destFilePath
        echo "`date "+%Y/%m/%d %H:%M:%S"`***** END   ${e} Deploy *****"
        echo ""
    done

    rm -f $triggerFilePath/$triggerFileName 

    echo "`date "+%Y/%m/%d %H:%M:%S"`********** END   Deploy "
    echo ""
}

normal () {
    # ディレクトリ監視
    while read -r f; do
        if [ $f = $triggerFileName ] ; then
            backup
            deploy
        fi
        if [ $f = $restoreFileName ] ; then
            restore
            deploy
        fi
    done < <(inotifywait --format '%f' -e create -m $triggerFilePath)
}

restore() {

    echo "`date "+%Y/%m/%d %H:%M:%S"`********** BEGIN Restore "

    # 過去のバックアップの最新を取得
    for newest in `ls -dt $backupPath/*`; do
        break
    done

    if [ -z $newest ]; then
        exit 1
    fi

    # 最新のバックアップからアップ用ディレクトリにファイルを復元
    rm -r $srcFilePath/*
    cp -pr $newest/* $srcFilePath

    rm -f $triggerFilePath/$restoreFileName 

    echo "`date "+%Y/%m/%d %H:%M:%S"`********** END   Restore "
    echo ""
}


# 重複プロセスの監視
isAlive=`ps -ef | grep "$processName" | grep -v grep | grep -v srvchk | wc -l`
if [ $isAlive = 1 ]; then
    echo "started."
    exit
fi

if [ ! -z "$1" ] && [ $1 = 'deploy' ]; then
    # 即時実行
    backup
    deploy
elif [ ! -z "$1" ] && [ $1 = 'restore' ]; then
    # 復元
    restore
    deploy
else
    # 監視状態の場合は、トリガー用ディレクトリにログを吐く
    exec >> $triggerFilePath/deploy.log 2>&1
    # 終了時にinotifywaitも終了させる
    trap 'pgrep -f inotifywait | xargs kill' EXIT
    # 監視実行
    normal
fi
