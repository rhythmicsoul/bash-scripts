#!/usr/bin/env bash

main(){
    if [[ $(id -u) != 0 ]];then 
        echo "Error: Please Execute the Script with root permissions."
    fi
    
    WORKDIR="/tmp/generate-nginx-confs"
    mkdir -p "$WORKDIR"
    NGINX_CONF_DIR="/etc/nginx"
    UPSTREAM_CONF="$NGINX_CONF_DIR/conf.d/upstream_servers.conf"
    VHOST_CONF_DIR="$NGINX_CONF_DIR/sites-enabled"
    VHOST_CONF_AVAILABLE_DIR="$NGINX_CONF_DIR/sites-available"

    ACTION="$1"
    if [[ "$ACTION" == "upstream" ]]; then
        upstream "$@"
    elif [[ "$ACTION" == "server" ]]; then
        server "$@"
    fi
}

check_func_args() {
    local name_of_function=$1
    local num_of_args=$2
    local expected_num_of_args=$3
    local func_line_number=$4

    if [[ $# -lt 4 ]]; then
        (>&2 echo "Error: $0 function expects minimum of 4 arguments.")
        exit 1
    else
        if [[ $num_of_args -lt $expected_num_of_args ]]; then
            (>&2 echo "Error: $name_of_function function expects minimum of $expected_num_of_args arguments. Occured in $func_line_number line number.")
            exit 1
        fi
    fi
}

upstream(){
    local action="$2"

    if [[ "$action" == "list" ]]; then
        list_upstream "$UPSTREAM_CONF"
    elif [[ "$action" == "add" ]]; then
		check_func_args "${FUNCNAME[0]}()" "$#" "4" "${BASH_LINENO[0]}"
        add_upstream "$3" "$4"
    elif [[ "$action" == "delete" ]]; then
		check_func_args "${FUNCNAME[0]}()" "$#" "3" "${BASH_LINENO[0]}"
        delete_upstream "$3"
    fi
}

server(){
    local action="$2"

    if [[ "$action" == "list" ]]; then
        if [[ -z "$3" ]]; then
            list_servers "$VHOST_CONF_DIR"
        else
            show_server_conf "$3"
        fi
    elif [[ "$action" == "add" ]]; then
		check_func_args "${FUNCNAME[0]}()" "$#" "4" "${BASH_LINENO[0]}"
		add_server "$3" "$4"
    elif [[ "$action" == "delete" ]]; then
		check_func_args "${FUNCNAME[0]}()" "$#" "3" "${BASH_LINENO[0]}"
        delete_server "$3"
    fi
}

list_upstream(){
    cat $1
}

add_upstream(){
	check_func_args "${FUNCNAME[0]}()" "$#" "2" "${BASH_LINENO[0]}"
    local name="$1"
    local ip="$2"
    local tmpconf="$WORKDIR/upstream_servers.conf"

    cat "$UPSTREAM_CONF" > "$tmpconf"
    cat << EOF >> "$tmpconf"

upstream $name {
    keepalive 100;
    server $ip;
}
EOF

    mv "$tmpconf" "$UPSTREAM_CONF"
    echo "Added the upstream server $name with IP address $ip"
    if ! check_reload_nginx; then 
        echo "Reverting the upstream configuration changes..." && delete_upstream "$name"
    fi
}

delete_upstream(){
	check_func_args "${FUNCNAME[0]}()" "$#" "1" "${BASH_LINENO[0]}"
    local name="$1"
    local tmpconf="$WORKDIR/upstream_servers.conf"

    sed -e "/upstream $name\s{/,/}/d" "$UPSTREAM_CONF" > "$tmpconf"

    cp "$UPSTREAM_CONF" "$UPSTREAM_CONF.bak"
    mv "$tmpconf" "$UPSTREAM_CONF"
    echo "Deleted upstream server $name"

    if ! check_reload_nginx; then 
        echo "Reverting the upstream configuration changes..." && cp "$UPSTREAM_CONF.bak" "$UPSTREAM_CONF" && check_reload_nginx
    fi
}

list_servers(){
    local vhost_conf_dir="$1"

    ls "$vhost_conf_dir" | sed -e "s/.conf//"
}

show_server_conf() {
    local server_name="$1"

    cat "$VHOST_CONF_DIR/$server_name.conf"
}

add_server(){
	check_func_args "${FUNCNAME[0]}()" "$#" "2" "${BASH_LINENO[0]}"
    local server_name="$1"
    local upstream="$2"
    local tmpconf="$WORKDIR/$server_name.conf"

    cat << EOF > "$tmpconf"
server {
        listen 80;
        server_name $server_name www.$server_name;
        access_log /var/log/nginx/$server_name/access.log;
        error_log /var/log/nginx/$server_name/error.log;

        gzip on;
        gzip_types *;
        gzip_proxied any;
        gzip_min_length 1000;

        location / {
                location /stalker_portal/server/adm {
                        if (\$remote_addr = 192.168.222.9) {
                             return 404;
                        }
                        try_files \$uri/ @pass_proxy;
                }
                try_files \$uri/ @pass_proxy;
        }

        location @pass_proxy {
                proxy_pass http://$upstream;
                proxy_http_version 1.1;
                proxy_set_header Connection "";
                proxy_set_header        Host               \$host;
                proxy_set_header        X-Real-IP          \$remote_addr;
                proxy_set_header        X-Forwarded-For    \$proxy_add_x_forwarded_for;               
                proxy_set_header        X-Forwarded-Host   \$host:80;
                proxy_set_header        X-Forwarded-Server \$host;
                proxy_set_header        X-Forwarded-Port   80;
                proxy_set_header        X-Forwarded-Proto  http;

                keepalive_timeout       600;
                keepalive_requests      100000;
        }

}
EOF
	mkdir -p "/var/log/nginx/$server_name"
    mv "$tmpconf" "$VHOST_CONF_AVAILABLE_DIR"
    ln -s "$VHOST_CONF_AVAILABLE_DIR/$server_name.conf" "$VHOST_CONF_DIR/$server_name.conf"
	echo "Server $server_name added successfully"

    if ! check_reload_nginx; then 
        echo "Reverting the changes made in the server configuration..." && delete_server "$server_name"
    fi
}

delete_server(){
	check_func_args "${FUNCNAME[0]}()" "$#" "1" "${BASH_LINENO[0]}"
    local server_name="$1"

    if [[ -f "$VHOST_CONF_AVAILABLE_DIR/$server_name.conf" ]]; then
        unlink "$VHOST_CONF_DIR/$server_name.conf"
        cp "$VHOST_CONF_AVAILABLE_DIR/$server_name.conf" "$VHOST_CONF_AVAILABLE_DIR/$server_name.conf.bak"
        rm -f "$VHOST_CONF_AVAILABLE_DIR/$server_name.conf"
    else
        echo "Server Configuration not found at $VHOST_CONF_AVAILABLE_DIR"
        exit 10
    fi

    echo "Deleted Server $server_name successfully"
    check_reload_nginx
}

check_reload_nginx(){
    echo "Checking nginx configuration....." && nginx -t || return 20
    echo "Reloading Nginx Configuration...." 
    if ! nginx -s reload; then
        echo "Nginx Configuration Reload Failed" && return 21
    fi
    echo "Nginx Conifguration Reloaded Successfully"
}

main "$@"
