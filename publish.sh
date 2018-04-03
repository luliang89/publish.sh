#!/bin/bash

#运行本脚本需要安装svn nodejs 


#######测试环境
#./publish.sh -s "http://192.168.0.90/svn/vendomagic/platform/mcloud/api/trunk" -h "ifood360@192.168.0.68" -d "/data/ifood360/api" -e "mcloud-api"
#######测试环境


#######正式环境
#./publish.sh -s "http://192.168.0.90/svn/vendomagic/platform/mcloud/api/trunk" -h "ifood360@192.168.0.68" -d "/data/ifood360/api" -p 12367
#######正式环境



function question () {
    echo $1
    read yes
    
    if test $yes == 'y'
    then
        return 0
    fi
    return 1
}

function build () {

    svn=$1

    svn_rev=$2
    
    echo "Last Changed Rev: ${svn_rev}"

    if [ -z ${svn_rev} ]
    then 
        echo "无法获取svn版本号"
        exit 1
    fi

    publish_dir="$( pwd )/publish"
    local_dir="${publish_dir}/${svn_rev}"
    if [ -e ${local_dir} ]
    then
        rm -rf ${local_dir}
        if test $? != 0
        then
            exit 1
        fi
    fi

    #下载源代码
    svn export ${svn} ${local_dir}
    if test $? != 0
    then
    exit 1
    fi
    printf "\n\n"
    echo '下载源代码完成，开始安装nodejs依赖包…'

    #安装npm私服包
    cd ${local_dir}

    #安装npm包，并编译
    #npm run install-private && npm install --production
    npm install --production
    if test $? != 0
    then
    exit 1
    fi
    printf "\n\n"
    echo 'nodejs运行依赖包安装完成，开始压缩…'
    tar -cvf node_modules.tgz node_modules

    printf "\n\n"
    echo '开始安装nodejs编译依赖包，并编译…'
    npm i && npm run build
    if test $? != 0
    then
    exit 1
    fi

    printf "\n\n"
    echo '编译完成，开始打包完整的项目包…'

    #复制其他文件
    src='build/src/'
    cp node_modules.tgz ${src}
    cp package.json "${src}package.json"
    
    cd ${src}
    tar -xvf node_modules.tgz
    rm -f node_modules.tgz

    cd ..
    mv src ${svn_rev}
    tar -zcvf "${svn_rev}.tgz" ${svn_rev} --exclude *.js.map
    if test $? != 0
    then
    exit 1
    fi

    mv "${svn_rev}.tgz" "${publish_dir}/${svn_rev}.tgz"
    cd ${publish_dir}
    rm -rf ${svn_rev}
    cd ..

    printf "\n\n"
    echo "项目打包完成:${src}."
}

while getopts s:h:d:p:e: arg
do
    case ${arg} in
        s)
            svn=$OPTARG
            ;;
        h)
            host=$OPTARG
            ;;
        p)
            port=$OPTARG
            ;;
        d)
            dir=$OPTARG
            ;;
        e)
            env=$OPTARG
            ;;
        ?)
            echo "unkonw argument"
            exit 1
            ;;
    esac
done

if [ -z ${host} ]
then 
    echo "-h is null"
    exit 1
fi

if [ -z ${dir} ]
then 
    echo "-d is null"
    exit 1
fi

svn_rev=`svn info "${svn}" | grep "Last Changed Rev" | tr -cd "[0-9]"`

question '是否编译项目？(y/n)'
if test $? == 0
then
    build ${svn} ${svn_rev}
fi

printf "\n\n"
question '是否现在上传项目包？(y/n)'
if test $? != 0
then
    exit 1 
fi

#进入已编译好的目录
cd publish

#上传文件
if [ -z ${port} ]
then
    sftp_str=${host}
else
    sftp_str="-oPort=${port} ${host}"
fi

printf "\n\n"
echo "上传压缩包，请输入服务器ssh密码："
sftp ${sftp_str} <<EOF
put "${svn_rev}.tgz"
exit
EOF

printf "\n\n"
echo "项目包上传完成。"

##登录服务器、解压、重启进程
if [ -z ${port} ]
then
    ssh_str=${host}
else
    ssh_str="${host} -p ${port}"
fi

subdir=`echo ${dir} | rev | cut -d '/' -f 1 | rev`
backdir=${subdir}`date "+%Y%m%d"`

printf "\n\n"
echo "登录服务器，请输入服务器ssh密码："
ssh ${ssh_str} <<EOF

cdir=\`pwd\`
tarpath=\"\${cdir}/${svn_rev}.tgz\"

if [ -d ${dir} ]
then
    cd ${dir}/..
    cp -rf ${subdir} ${backdir}
else
    mkdir ${dir}
fi

printf "\n\n"
echo "复制压缩包${svn_rev}.tgz至${dir}/.."
cd \${cdir}
mv -f ${svn_rev}.tgz ${dir}/..
if [ \$? != 0 ]
then
 exit 1 
fi

printf "\n\n"
echo "解压压缩包${svn_rev}.tgz"
cd ${dir}/..
tar -xvf ${svn_rev}.tgz
rm -f ${svn_rev}.tgz

docker-compose stop ${env}

printf "\n\n"
echo "删除${subdir}"
rm -rf ${subdir}

printf "\n\n"
echo "将${svn_rev}重命名为${subdir}"
mv ${svn_rev} ${subdir}

printf "\n\n"
echo "创建日志文件目录"
cd ${subdir}
mkdir logs

printf "\n\n"
echo "重启docker进程…"

docker-compose restart ${env}

exit
EOF

printf "\n\n"
echo '发布完成！'


