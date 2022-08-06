#!/bin/bash
#
# gedit-from-rl.sh -- gedit riscv-linux articles with absolute image path
#

#
# Usage: ./tools/gedit-from-rl.sh ../../labs/riscv-linux/articles/20220724-virt-mode.md
#
# 0. Clone the repo to ~/Develop/cloud-lab/labs/
# 1. Firstly, execute the above command
# 2. Fix up the image address
#

TOP_DIR=$(cd $(dirname $0)/../ && pwd)

rl_repo=https://gitee.com/tinylab/riscv-linux
rl_dir=~/Develop/cloud-lab/labs/riscv-linux
rl_articles=$rl_dir/articles
rl_images=$rl_articles/images/

# get target article
article=$1
[ -z "$article" ] && echo "Usage: $0 /path/to/article" && exit 1
[ ! -f "$article" ] && echo "ERR: No such file: $article" && exit 1

# update rl repo
if [ ! -d $rl_dir ]; then
  dir=$(dirname $rl_dir)
  mkdir -p $dir
  pushd $dir
  git clone $rl_repo
  popd
fi

update=$2
if [ "$update" = "1" ]; then
  pushd $rl_dir
  git checkout master
  git pull
  popd
fi

# get target article name
echo $article
orig_article=$(basename $article | sed -e "s/[0-9]*//")
date_string=$(date +"%Y-%m-%d-%H-%M-%S")
target_article=${date_string}${orig_article}
subimages_dir=$(grep -m1 '](images/' $article | sed -e 's%.*](images/\([^/]*\)/.*%\1%')
target_images=https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/
_target_article=$(mktemp -d)/$target_article

echo "LOG: Copy article from $rl_dir to $TOP_DIR/_posts/"
cat $article >> $_target_article

if [ -n "$subimages_dir" ]; then
  echo "LOG: Copy images if there are"
  sed -i -e "s%](images/%]($target_images%g" $_target_article
fi

echo "LOG: Remove original title"
sed -i -e '/^# .*/d' $_target_article

echo "LOG: Gedit article: $_target_article"

gedit $_target_article
