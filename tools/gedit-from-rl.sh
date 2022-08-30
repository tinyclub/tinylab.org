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

if [ -z "$article" ]; then
  echo
  echo "LOG: available articles"
  echo

  ls -1 $rl_articles | grep -v README.md | grep -n --color=auto .md

  echo
  read -p "LOG: Please choose one key? " key
  echo

  ls -1 $rl_articles | grep -v README.md | grep -n .md | grep --color=auto $key
  if [ $? -ne 0 ]; then
    echo
    read -p "LOG: No one is found with key: '$key', please choose one of them by the number? " one
    echo
    ls -1 $rl_articles | grep -v README.md | grep --color=auto -n .md
    echo
  else
    echo
    read -p "LOG: Please choose one of above by the number? " one
    echo
  fi

  ls -1 $rl_articles | grep -v README.md | grep -n .md | grep "^$one:"
  if [ $? -ne 0 ]; then
    echo "ERR: The number: $one may be invalid"
    exit 1
  else
    choose="$(ls -1 $rl_articles | grep -v README.md | grep -n .md | grep "^$one:" | cut -d ':' -f2)"
  fi

  article=$rl_articles/$choose

  echo "LOG: current selected article: $article"
fi


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
orig_article=$(basename $article | sed -e "s/[0-9]*//")
date_string=$(date +"%Y-%m-%d-%H-%M-%S")
target_article=${date_string}${orig_article}
articles_path=https://gitee.com/tinylab/riscv-linux/blob/master/articles/
subimages_dir=$(egrep -m1 "\]\(./images/|\]\(/images/|\]\(images/" $article | sed -e 's%.*](/images/\([^/]*\)/.*%\1%' | sed -e 's%.*](./images/\([^/]*\)/.*%\1%' | sed -e 's%.*](images/\([^/]*\)/.*%\1%')
target_images=https://gitee.com/tinylab/riscv-linux/raw/master/articles/images/
_target_article=$(mktemp -d)/$target_article

echo "LOG: Copy article from $rl_dir to $TOP_DIR/_posts/"
cat $article >> $_target_article

if [ -n "$subimages_dir" ]; then
  echo "LOG: Copy images if there are"
  sed -i -e "s%](/images/%]($target_images%g" $_target_article
  sed -i -e "s%](images/%]($target_images%g" $_target_article
  sed -i -e "s%](./images/%]($target_images%g" $_target_article
fi

sed -i -e '/[^\!]\[[^(]*\]([^h#].*)/{s%\([^\!][[^(]*](\)[\./]*%\1'$articles_path'%g}' $_target_article
sed -i -e '/^\[[0-9]\{1,\}\]: [^h#].*/{s%\(^\[[0-9]\{1,\}\]: \)[\./]*%\1'$articles_path'%g}' $_target_article

echo "LOG: Fix up top information"
sed -i -e "s% *<br/>%%g" $_target_article

echo "LOG: Strip ending whitespaces"
sed -i -e "s%[[:space:]]*$%%g" $_target_article

echo "LOG: Remove original title"
sed -i -e '/^# .*/d' $_target_article

echo "LOG: Gedit article: $_target_article"

# Easier copy
copy2clipboard ()
{
  [ -z "$1" ] && return 1

  clip=""
  for c in xsel xclip clip
  do
    which $c >/dev/null 2>&1 && clip=$c && break
  done

  case "$clip" in
    xsel)  clip_cmd="$clip -b" ;;
    xclip) clip_cmd="$clip -selection clipboard" ;;
    clip)  clip_cmd="$clip" ;;
    *)     echo "ERR: No clipboard command found" && return 1 ;;
  esac

  cat "$1" | eval "$clip_cmd"
}

# Copy to clipboard
copy2clipboard $_target_article

gedit $_target_article
