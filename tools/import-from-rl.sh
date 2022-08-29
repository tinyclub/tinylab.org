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
articles_path=https://gitee.com/tinylab/riscv-linux/blob/master/articles/
subimages_dir=$(egrep -m1 "\]\(./images/|\]\(/images/|\]\(images/" $article | sed -e 's%.*](/images/\([^/]*\)/.*%\1%' | sed -e 's%.*](./images/\([^/]*\)/.*%\1%' | sed -e 's%.*](images/\([^/]*\)/.*%\1%')
rl_subimages=$rl_images/$subimages_dir
target_images=wp-content/uploads/2022/03/riscv-linux/images/

_target_article=$TOP_DIR/_posts/$target_article
_target_images=$TOP_DIR/$target_images

# get top header info
title="$(grep -m1 '^# ' $article | cut -d ' ' -f2-)"
permalink="$(basename $article | sed -e 's/[0-9]*-//;s/.md$//')"
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

sed -i -e '/[^\!]\[[^(]*\]([^h#i].*)/{s%\([^\!][[^(]*](\)[\./]*%\1'$articles_path'%g}' $_target_article
sed -i -e '/^\[[0-9]\{1,\}\]: [^h#i].*/{s%\(^\[[0-9]\{1,\}\]: \)[\./]*%\1'$articles_path'%g}' $_target_article

echo "LOG: Fix up top information"
sed -i -e "s% *<br/>%%g" $_target_article

echo "LOG: Strip ending whitespaces"
sed -i -e "s%[[:space:]]*$%%g" $_target_article

echo "LOG: Remove original title"
sed -i -e '/^# .*/d' $_target_article

echo "LOG: Use jekyll plugin"
sed -i -e '/``` *mermaid/,/```/{s/``` *mermaid$/<pre><div class="mermaid">/;s/```$/<\/div><\/pre>/;s/^ *//}' $_target_article

echo "LOG: Target article: $_target_article"
echo "LOG: Target images: $_target_images"
