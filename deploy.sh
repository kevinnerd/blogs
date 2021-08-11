npx hexo generate
rsync -uvz public/* $1:/var/html/
