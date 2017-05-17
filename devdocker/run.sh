#!/bin/bash

# basic services startup
/etc/init.d/rsyslog start
/etc/init.d/cron start
/etc/init.d/ssh start
/etc/init.d/exim4 start

# fix devdocker uid so that it matches host user uid
groupmod -g $GROUP_ID devdocker # will fail if $GROUP_ID already exists, so that devdocker is the default group
usermod -u $USER_ID -g $GROUP_ID devdocker && \
    chown -R $USER_ID:$GROUP_ID /var/log/mysql && \
    chown -R $USER_ID:$GROUP_ID /var/lib/mysql
chfn devdocker -f "$USER_FULLNAME"

# force debian-sys-maint
sed -i 's/debian-sys-maint/root/g' /etc/mysql/debian.cnf
sed -i 's/debian-sys-maint/root/g' /etc/mysql/debian.cnf
sed -i "s/^password = .*/password = $MYSQL_FORCED_ROOT_PASSWORD/g" /etc/mysql/debian.cnf

# start mysql, initializing DB if necessary
if [ ! -d /var/lib/mysql/mysql ]; then
    logger "Initializing mysql database"
    sudo rm -f /var/lib/mysql/.gitignore
    sudo -u devdocker mysql_install_db --user=devdocker
fi

# force root password and open to outside
MYSQL_RUNNING = 0;
echo "" > /mysql-force-password.sql && \
    chown devdocker:devdocker /mysql-force-password.sql && \
    chmod 400 /mysql-force-password.sql && \
    echo "USE mysql; " >> /mysql-force-password.sql && \
    echo "CREATE TEMPORARY TABLE devdocker_tmp ENGINE=MyISAM SELECT * FROM user WHERE User='root' LIMIT 1; " >> /mysql-force-password.sql && \
    echo "UPDATE devdocker_tmp SET Host='%'; " >> /mysql-force-password.sql && \
    echo "REPLACE INTO user SELECT * FROM devdocker_tmp; " >> /mysql-force-password.sql && \
    echo "DROP TABLE devdocker_tmp; " >> /mysql-force-password.sql && \
    echo "UPDATE user SET Password=PASSWORD('$MYSQL_FORCED_ROOT_PASSWORD') WHERE User='root'; " >> /mysql-force-password.sql && \
    echo "FLUSH PRIVILEGES; " >> /mysql-force-password.sql
echo "" > /root/.my.cnf && \
    chmod 400 /root/.my.cnf && \
    echo "[client]" > /root/.my.cnf && \
    echo "user=root" >> /root/.my.cnf && \
    echo "host=127.0.0.1" >> /root/.my.cnf && \
    echo "password=$MYSQL_FORCED_ROOT_PASSWORD" >> /root/.my.cnf && \
    cp -p /root/.my.cnf /home/devdocker/.my.cnf && \
    chown devdocker: /home/devdocker/.my.cnf && \
    mkdir -p /var/run/mysqld && \
    chown devdocker: /var/run/mysqld && \
    sudo -u devdocker mysqld_safe --skip-grant-tables --skip-networking --init-file=/mysql-force-password.sql &
# wait for mysql to startup in "reset password mode"
while ! [[ "$MYSQL_RUNNING" == "1" ]]; do
    # limit to 60 retries (12s)
    ((c++)) && ((c==60)) && logger "Warning: giving up mysql first startup" && break
    sudo /usr/bin/mysqladmin --defaults-file=/etc/mysql/debian.cnf ping > /dev/null 2>&1 ; MYSQL_RUNNING=$(( ! $? ));
    sleep 0.2
done
# then kill mysql and wait until it dies
/etc/init.d/mysql stop
while ! [[ "$MYSQL_RUNNING" == "0" ]]; do
    # limit to 60 retries (12s)
    ((c++)) && ((c==60)) && logger "Warning: giving up mysql password reset" && break
    sudo /usr/bin/mysqladmin --defaults-file=/etc/mysql/debian.cnf ping > /dev/null 2>&1 ; MYSQL_RUNNING=$(( ! $? ));
    sleep 0.2
done
# and start mysql up again
/etc/init.d/mysql start

# wait for mysqld_safe startup and install phpmyadmin database if necessary
if [ ! -d /var/lib/mysql/phpmyadmin ]; then
    logger "Initializing phpmyadmin database"
    while ! [[ "$MYSQL_RUNNING" == "1" ]]; do
        # limit to 60 retries (12s)
        ((c++)) && ((c==60)) && logger "Warning: giving up phpmyadmin database initialization" && break
        sudo /usr/bin/mysqladmin --defaults-file=/etc/mysql/debian.cnf ping > /dev/null 2>&1 ; MYSQL_RUNNING=$(( ! $? ));
        sleep 0.2
    done
    zcat /usr/share/doc/phpmyadmin/examples/create_tables.sql.gz | mysql
fi

# blackfire configuration
sed -i "s/DEVDOCKER_BLACKFIRE_CLIENT_ID/$BLACKFIRE_CLIENT_ID/g" /home/devdocker/.blackfire.ini
sed -i "s/DEVDOCKER_BLACKFIRE_CLIENT_TOKEN/$BLACKFIRE_CLIENT_TOKEN/g" /home/devdocker/.blackfire.ini
sed -i "s/DEVDOCKER_BLACKFIRE_SERVER_ID/$BLACKFIRE_SERVER_ID/g" /etc/blackfire/agent
sed -i "s/DEVDOCKER_BLACKFIRE_SERVER_TOKEN/$BLACKFIRE_SERVER_TOKEN/g" /etc/blackfire/agent
sed -i "s/^;blackfire.server_id =.*/blackfire.server_id = $BLACKFIRE_SERVER_ID/g" /etc/php5/mods-available/blackfire.ini
sed -i "s/^;blackfire.server_token =.*/blackfire.server_token = $BLACKFIRE_SERVER_TOKEN/g" /etc/php5/mods-available/blackfire.ini
sed -i "s/^;blackfire.log_file = .*/blackfire.log_file = \/tmp\/blackfire.log/g" /etc/php5/mods-available/blackfire.ini
/etc/init.d/blackfire-agent start

# conditionnal services startup
if [[ "$START_DOCKER_IN_DOCKER" == "1" ]]; then
    /etc/init.d/docker start
fi
if [[ "$START_MEMCACHED" == "1" ]]; then
    /etc/init.d/memcached start
fi
if [[ "$START_VARNISH" == "1" ]]; then
    /etc/init.d/varnish start
fi
if [[ "$START_REDIS" == "1" ]]; then
    /etc/init.d/redis-server start
fi
if [[ "$START_ELK" == "1" ]]; then
    /etc/init.d/elasticsearch start
    /etc/init.d/kibana start
    /etc/init.d/metricbeat start
fi

# start apache
source /etc/apache2/envvars
exec apache2 -D FOREGROUND

