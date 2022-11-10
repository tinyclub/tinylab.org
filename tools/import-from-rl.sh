#!/bin/bash
#
# import-from-rl.sh -- import articles from riscv-linux/articles
#

#
# Usage: ./tools/import-from-rl.sh ../../labs/riscv-linux/articles/20220724-virt-mode.md
#
# 0. Clone the repo to ~/Develop/cloud-lab/labs/
# 1. Firstly, execute the above command
# 2. Fix up the author info
# 3. Edit the description info, based on the 'Content' info and the 'Section 1'
# 4. Add missing tags from the 'Content' info
# 5. Run it with the command 'tools/docker/run tinylab.site'
#

TOP_DIR=$(cd $(dirname $0)/../ && pwd)

rl_repo=https://gitee.com/tinylab/riscv-linux
rl_dir=~/Develop/cloud-lab/labs/riscv-linux
rl_articles=$rl_dir/articles
rl_images=$rl_articles/images/
site_url=https://tinylab.org

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

  ls -1 $rl_articles | grep -v README.md | grep -n .md | grep -i --color=auto "$key"
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

[ -z "$update" ] && update=$2
if [ "$update" = "1" ]; then
  git pull

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
articles_path=https://gitee.com/tinylab/riscv-linux/blob/master/articles/
subimages_dir=$(egrep -m1 "\]\(./images/|\]\(/images/|\]\(images/" $article | sed -e 's%.*](/images/\([^/]*\)/.*%\1%' | sed -e 's%.*](./images/\([^/]*\)/.*%\1%' | sed -e 's%.*](images/\([^/]*\)/.*%\1%')
rl_subimages=$rl_images/$subimages_dir
target_images=wp-content/uploads/2022/03/riscv-linux/images/

_target_article=$TOP_DIR/_posts/$target_article
_target_images=$TOP_DIR/$target_images

# get top header info
title="$(grep -m1 '^# ' $article | cut -d ' ' -f2-)"
permalink="$(basename $article | sed -e 's/[0-9]*-//;s/.md$//')"
full_permalink="${site_url}/${permalink}/"
desc="$title"

# check mermaid
if grep -q mermaid $article; then
  plugin="mermaid"
fi

# structure, for desc edit
pushd $rl_articles
author="$(git log --pretty=short $(basename $article) | grep Author | tail -1 | cut -d':' -f2 | cut -d '<' -f1 | sed -e 's/^ *//g;s/ *$//g')"
popd

_author="$(grep -m1 -ir '$author' _posts/ | tail -1 | cut -d ':' -f1 | xargs -i grep -m1 author {} | cut -d ':' -f2- | sed 's/^ *//g' | tr -d "'" | tr -d '"')"

# show them
echo "LOG: Basic information"
echo
echo Title: $title
echo Author: $author
[ -z "$_author" ] && _author="$author"
echo _Author: $_author
echo

echo "LOG: Contents"
echo
grep "^##" $article
echo

# remove old drafts
rm -f $TOP_DIR/_posts/*$orig_article

echo "LOG: Generate top header"
cat <<EOF > $_target_article
---
layout: post
author: '$_author'
title: '$title'
draft: false
plugin: '$plugin'
album: 'RISC-V Linux'
license: 'cc-by-nc-nd-4.0'
permalink: /$permalink/
description: '$desc'
category:
  - 开源项目
  - Risc-V
tags:
  - Linux
  - RISC-V
---

EOF

echo "LOG: Copy article from $rl_dir to $TOP_DIR/_posts/"
cat $article >> $_target_article


if [ -n "$subimages_dir" ]; then
  echo "LOG: Copy images if there are"
  cp -r $rl_subimages $_target_images
  sed -i -e "s%](/images/%](/$target_images%g" $_target_article
  sed -i -e "s%](images/%](/$target_images%g" $_target_article
  sed -i -e "s%](./images/%](/$target_images%g" $_target_article
fi

sed -i -e '/[^\!]\[[^(]*\]([^h#].*)/{s%\([^\!][[^(]*](\)[\./]*%\1'$articles_path'%g}' $_target_article
sed -i -e '/[^\!]\[[^(]*\](.*\/articles\/images\/.*)/{s@/blob/@/raw/@g}' $_target_article
sed -i -e '/^\[[0-9]\{1,\}\]: [^h#].*/{s%\(^\[[0-9]\{1,\}\]: \)[\./]*%\1'$articles_path'%g}' $_target_article
sed -i -e '/^\[[0-9]\{1,\}\]: .*\/articles\/images\/.*/{s@/blob/@/raw/@g}' $_target_article

echo "LOG: Fix up top information"
sed -i -e "s% *<br/>%%g" $_target_article

echo "LOG: Strip ending whitespaces"
sed -i -e "s%[[:space:]]*$%%g" $_target_article

echo "LOG: Remove original title"
sed -i -e '/^\s*```/,/^\s*```/!{/^# .*/d}' $_target_article

echo "LOG: Use jekyll plugin"
sed -i -e '/``` *mermaid/,/```/{s/``` *mermaid$/<pre><div class="mermaid">/;s/```$/<\/div><\/pre>/;s/^ *//}' $_target_article

echo "LOG: Target article: $_target_article"
echo "LOG: Target images: $_target_images"

echo "LOG: Add files"

git add $_target_article $_target_images

echo "LOG: Commit files"

git commit -s -m "add $permalink"

echo
echo "LOG: It is time to push this article and its images to remote repos"

echo
read -p "LOG: Are you ready to push? (y/n) " push
echo

if [ "$push" = "y" -o "$push" = "yes" -o "$push" = "Y" -o "$push" = "YES" ]; then
  gitee_push="git push gitee:tinylab/tinylab.org"
  github_push="git push github:tinyclub/tinylab.org"

  for repo in gitee github
  do
    eval cmd=\${${repo}_push}
    echo "LOG: Pushing to repo with: '$cmd'"
    echo
    eval $cmd
    echo
    if [ $? -ne 0 ]; then
      if [ "$repo" = "github" ]; then
        echo
        echo "ERR: Please run '$cmd' again, otherwise, the permalink is invalid."
        echo
      fi
    else
      echo
      echo "LOG: pushed to $repo"
      echo
    fi
  done

fi

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

  echo "$1" | eval "$clip_cmd"
}

# Copy to clipboard
copy2clipboard $full_permalink

echo "LOG: Please use the following permalink"
echo
echo "$full_permalink"
echo

echo "LOG: Generate the file for mdnice.com"

$TOP_DIR/tools/gedit-from-rl.sh "$article"
