#!/bin/bash
# Installer for GitLab on RHEL 6 (Red Hat Enterprise Linux and CentOS)

# Define the public hostname
export GL_HOSTNAME='10.136.114.88'

# Install from this GitLab branch
export GL_GIT_BRANCH="5-2-stable"


# Define MySQL gitlab password
MYSQL_PW='qzdwqsc1'

# Exit on error

die()
{
  # $1 - the exit code
  # $2 $... - the message string

  retcode=$1
  shift
  printf >&2 "%s\n" "$@"
  exit $retcode
}

echo "### Check OS (we check if the kernel release contains el6)"
uname -r | grep "el6" || die 1 "Not RHEL or CentOS 6 (el6)"

# Install base packages

yum -y groupinstall 'Development Tools'

# Ruby

yum -y install ruby-tcltk vim-enhanced httpd readline readline-devel ncurses-devel gdbm-devel glibc-devel \
               tcl-devel openssl-devel curl-devel expat-devel db4-devel byacc \
	       sqlite-devel gcc-c++ libyaml libyaml-devel libffi libffi-devel \
	       libxml2 libxml2-devel libxslt libxslt-devel libicu libicu-devel \
	       system-config-firewall-tui python-devel redis sudo mysql-server wget \
	       mysql-devel crontabs logwatch logrotate sendmail-cf qtwebkit qtwebkit-devel \
	       perl-Time-HiRes --enablerepo=epel-6-epel

curl --progress http://ftp.ruby-lang.org/pub/ruby/1.9/ruby-1.9.3-p392.tar.gz | tar xz
cd ruby-1.9.3-p392
./configure
make
make install



## Install core gems

gem install bundler

# Users

## Create a git user for Gitlab

adduser --system --create-home --shell /bin/bash --home-dir /home/git --comment 'GitLab' git
su - git -c 'git config --global user.name  "GitLab"'
su - git -c 'git config --global user.email "gitlab@10.136.114.88"'

# GitLab Shell
cd /home/git

## Clone gitlab-shell

su - git -c "git clone https://github.com/gitlabhq/gitlab-shell.git"
while [ $? -ne 0] && [$? -ne 128 ]
do
	su - git -c "git clone https://github.com/gitlabhq/gitlab-shell.git"
done


cd gitlab-shell
su - git -c "cd gitlab-shell;git git checkout v1.4.0"

## Edit configuration

su - git -c "cd gitlab-shell;cp config.yml.example config.yml"
sed -i "s/localhost/$GL_HOSTNAME/g" /home/git/gitlab-shell/config.yml

## Run setup

su - git -c "cd gitlab-shell;./bin/install"

## Automatically start redis
chkconfig redis on


## Start redis
service redis start


## Turn on autostart
chkconfig mysqld on

## Start mysqld
service mysqld start

#Create mysql user for Git

echo "FLUSH PRIVILEGES;" | mysql -u root
echo "CREATE USER 'gitlab'@'localhost' IDENTIFIED BY '$MYSQL_PW';" | mysql -u root

### Create the database
echo "CREATE DATABASE IF NOT EXISTS gitlabhq_production DEFAULT CHARACTER SET 'utf8' COLLATE 'utf8_unicode_ci';" | mysql -u root

## Set MySQL root password in MySQL
echo "GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON gitlabhq_production.* TO 'gitlab'@'localhost';" | mysql -u root

# GitLab
cd /home/git


## Clone GitLab
su - git -c "git clone https://github.com/gitlabhq/gitlabhq.git gitlab"
while [ $? -ne 0] && [$? -ne 128 ]
do
	su - git -c "git clone https://github.com/gitlabhq/gitlabhq.git gitlab"
done

cd /home/git/gitlab


## Checkout
su - git -c "cd gitlab;git checkout $GL_GIT_BRANCH"

## Configure GitLab


### Copy the example GitLab config
su - git -c "cd gitlab;cp config/gitlab.yml.example config/gitlab.yml"

### Change gitlabhq hostname to GL_HOSTNAME
sed -i "s/  host: localhost/  host: '$GL_HOSTNAME'/g" config/gitlab.yml

### Change the from email address
sed -i "s/from: gitlab@localhost/from: gitlab@$GL_HOSTNAME/g" config/gitlab.yml

### Change LDAP config

chown -R git log/
chown -R git tmp/
chmod -R u+rwx  log/
chmod -R u+rwx  tmp/
su - git -c "mkdir /home/git/gitlab-satellites"
su - git -c "mkdir /home/git/gitlab/tmp/pids/"
su - git -c "mkdir /home/git/gitlab/tmp/sockets/"
chmod -R u+rwx  tmp/pids/
chmod -R u+rwx  tmp/sockets/
su - git -c "mkdir /home/git/gitlab/public/uploads"
chmod -R u+rwx  public/uploads
su - git -c "cd gitlab;cp config/puma.rb.example config/puma.rb"


### Copy database congiguration
su - git -c "cd gitlab;cp config/database.yml.mysql config/database.yml"

### Set MySQL root password in configuration file
sed -i "1,14s/secure password/$MYSQL_PW/g" config/database.yml

sed -i "1,14s/root/gitlab/g" config/database.yml

# Install Gems

## Install Charlock holmes

sed -i "1,1s/https/http/g" /home/git/gitlab/Gemfile
gem install charlock_holmes --version '0.6.9.4'

## For MySQL

su - git -c "cd gitlab;bundle install --deployment --without development test postgres"

# Initialise Database and Activate Advanced Features
su - git -c "cd gitlab;bundle exec rake gitlab:setup RAILS_ENV=production"


## Install init script
curl --output /etc/init.d/gitlab https://raw.github.com/gitlabhq/gitlabhq/5-2-stable/lib/support/init.d/gitlab
chmod +x /etc/init.d/gitlab


### Enable and start
chkconfig gitlab on

su - git -c  "cd gitlab;bundle exec rake gitlab:check RAILS_ENV=production"

service gitlab start


# Nginx

## Install
yum -y install nginx-sogou-lua.x86_64

## Configure
curl --output /usr/local/nginx/conf/vhosts/gitlab.conf https://raw.github.com/gitlabhq/gitlabhq/master/lib/support/nginx/gitlab

sed -i "1c\user git;" /usr/local/nginx/conf/nginx.conf

sed -i 's/listen.*/listen 80;/g' /usr/local/nginx/conf/vhosts/gitlab.conf
sed -i "s/YOUR_SERVER_FQDN/gitlab.sogou.com/g" /usr/local/nginx/conf/vhosts/gitlab.conf
sed -i "s/\/var\/log\/nginx/\/usr\/local\/nginx\/logs/g" /usr/local/nginx/conf/vhosts/gitlab.conf
## Start
service nginx start


echo "### Done ###############################################"
echo "#"
echo "#Change LDAP config by youself"
echo "#/home/git/gitlab/config/gitlab.yml"
echo "#"
echo "# Point your browser to:" 
echo "# http://$GL_HOSTNAME (or: http://<host-ip>)"
echo "# Default admin username: admin@local.host"
echo "# Default admin password: 5iveL!fe"
echo "#"
echo "###"
