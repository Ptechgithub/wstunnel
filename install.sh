#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
purple='\033[0;35m'
cyan='\033[0;36m'
white='\033[0;37m'
rest='\033[0m'

display_progress() {
    local duration=$1
    local sleep_interval=0.1
    local progress=0
    local bar_length=40
    local colors=("[41m" "[42m" "[43m" "[44m" "[45m" "[46m" "[47m")

    while [ $progress -lt $duration ]; do
        echo -ne "\r${colors[$((progress % 7))]}"
        for ((i = 0; i < bar_length; i++)); do
            if [ $i -lt $((progress * bar_length / duration)) ]; then
                echo -ne "█"
            else
                echo -ne "░"
            fi
        done
        echo -ne "[0m ${progress}%"
        progress=$((progress + 1))
        sleep $sleep_interval
    done
    echo -ne "\r${colors[0]}"
    for ((i = 0; i < bar_length; i++)); do
        echo -ne " "
    done
    echo -ne "[0m 100%"
    echo
}

# Check if running as root
root_access() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root."
        exit 1
    fi
}

# Detect Linux distribution
detect_distribution() {
    local supported_distributions=("ubuntu" "debian" "centos" "fedora")
    
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if [[ "${ID}" = "ubuntu" || "${ID}" = "debian" || "${ID}" = "centos" || "${ID}" = "fedora" ]]; then
            pm="apt-get"
            [ "${ID}" = "centos" ] && pm="yum"
            [ "${ID}" = "fedora" ] && pm="dnf"
        else
            echo "Unsupported distribution!"
            exit 1
        fi
    else
        echo "Unsupported distribution!"
        exit 1
    fi
}

#Check dependencies
check_dependencies() {
    root_access
    detect_distribution
    display_progress 8
    "${pm}" update -y
    local dependencies=("wget" "tar")
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo "${dep} is not installed. Installing..."
            sudo "${pm}" install "${dep}" -y
        fi
    done
}

#Check installed service 
check_installed() {
    if systemctl is-enabled --quiet wstunnel.service > /dev/null 2>&1; then
        echo "The WsTunnel service is already installed."
        exit 1
    fi
}

#Install wstunnel
install_wstunnel() {
    check_installed
    mkdir wstunnel && cd wstunnel
    check_dependencies
    
    # Determine system architecture
    if [[ $(arch) == "x86_64" ]]; then
        latest_version=$(curl -s https://api.github.com/repos/erebe/wstunnel/releases/latest | grep -oP '"tag_name": "\K(.*?)(?=")')
        wstunnel_file="wstunnel_${latest_version//v}_linux_amd64.tar.gz"
    elif [[ $(arch) == "aarch64" ]]; then
        wstunnel_file="wstunnel_${latest_version//v}_linux_arm64.tar.gz"
    elif [[ $(arch) == "armv7l" ]]; then
        wstunnel_file="wstunnel_${latest_version//v}_linux_armv7.tar.gz"
    elif [[ $(uname) == "Darwin" ]]; then
        wstunnel_file="wstunnel_${latest_version//v}_darwin_amd64.tar.gz"
    else
        echo "Unsupported architecture!"
        exit 1
    fi
    
    # Download and extract wstunnel
    wget "https://github.com/erebe/wstunnel/releases/download/${latest_version}/${wstunnel_file}" -q
    tar -xvf "$wstunnel_file" > /dev/null
    chmod +x wstunnel
    # Move wstunnel binary to /usr/local/bin (adjust if necessary)
    sudo mv wstunnel /usr/local/bin/wstunnel
    cd ..
    rm -rf wstunnel
}


# Get inputs
get_inputs() {
    clear
    PS3=$'\n'"# Please Enter your choice: "
    options=("External-[server]" "Internal-[client]" "Exit")

    select server_type in "${options[@]}"; do
        case "$REPLY" in
            1)
                read -p "Please Enter Connection Port (server <--> client) [default, 443]: " port
                port=${port:-443}
                read -p "Do you want to use TLS? (yes/no) [default: yes]: " use_tls
                use_tls=${use_tls:-yes}

                if [ "$use_tls" = "yes" ]; then
                    use_tls="wss"
                else
                    use_tls="ws"
                fi

                argument="server $use_tls://[::]:$port"
                break
                ;;
            2)
                read -p "Enter foreign IP [External-server]: " foreign_ip
                read -p "Please Enter Your config [vpn] Port :" config_port
                read -p "Please Enter Connection Port (server <--> client) [default, 443]: " port
                port=${port:-443}
                read -p "Do you want to use TLS? (yes/no) [default: yes]: " use_tls
                use_tls=${use_tls:-yes}

                if [ "$use_tls" = "yes" ]; then
                    use_tls="wss"
                else
                    use_tls="ws"
                fi
                
                echo -e "Enter connection type:
1) tcp  ${purple}[vless , vmess , trojan , ...]${rest}
2) udp  ${purple}[Wireguard , hysteria, tuic , ...]${rest}
3) socks5
4) stdio"
echo ""
read -p "Enter number (default is: 1--> tcp): " choice

                case $choice in
                    1) connection_type="tcp" ;;
                    2) connection_type="udp" ;;
                    3) connection_type="socks5" ;;
                    4) connection_type="stdio" ;;
                    *) connection_type="tcp" ;;
                esac
                read -p "Do you want to use SNI? (yes/no) [default: yes]: " use_sni
                use_sni=${use_sni:-yes}
			    if [ "$use_sni" = "yes" ]; then
			        read -p "Please Enter SNI [default: google.com]: " tls_sni
			        tls_sni=${tls_sni:-google.com}
			        tls_sni_argument="--tls-sni-override $tls_sni"
			    fi

                # Add ?timeout_sec=0 only for UDP
                if [ "$connection_type" = "udp" ]; then
                    timeout_argument="?timeout_sec=0"
                else
                    timeout_argument=""
                fi

                read -p "Do you want to add more ports? (yes/no) [default: no]: " add_port
				add_port=${add_port:-no}
				
				if [ "$add_port" == "yes" ]; then
				    read -p "Enter ports separated by commas (e.g., 2096,8080): " port_list
				    IFS=',' read -ra ports <<< "$port_list"
				
				    for new_port in "${ports[@]}"; do
				        argument+=" -L '$connection_type://[::]:$new_port:localhost:$new_port$timeout_argument'"
				    done
				fi

                argument="client -L '$connection_type://[::]:$config_port:localhost:$config_port$timeout_argument'$argument $use_tls://$foreign_ip:$port $tls_sni_argument"
                break
                ;;
            3)
                echo "Exiting..."
                exit 0 
                ;;
            *)
                echo "Invalid choice. Please Enter a valid number."
                ;;
        esac
    done

    create_service
}


get_inputs_Reverse() {
    clear
    PS3=$'\n'"# Please Enter your choice: "
    options=("Internal-[client]" "External-[server]" "Exit")

    select server_type in "${options[@]}"; do
        case "$REPLY" in
            1)
                read -p "Please Enter Connection Port (server <--> client) [default, 443]: " port
                port=${port:-443}
                read -p "Do you want to use TLS? (yes/no) [default: yes]: " use_tls
                use_tls=${use_tls:-yes}

                if [ "$use_tls" = "yes" ]; then
                    use_tls="wss"
                else
                    use_tls="ws"
                fi

                argument="server $use_tls://[::]:$port"
                break
                ;;
            2)
                echo -e "${yellow}Please install on [Internal-client] first. If you have installed it, press Enter to continue...${rest}"
                read -r
                read -p "Enter Internal IP [Internal-client]: " foreign_ip
                read -p "Please Enter Your config [vpn] Port :" config_port
                read -p "Please Enter Connection Port (server <--> client) [default, 443]: " port
                port=${port:-443}
                read -p "Do you want to use TLS? (yes/no) [default: yes]: " use_tls
                use_tls=${use_tls:-yes}

                if [ "$use_tls" = "yes" ]; then
                    use_tls="wss"
                else
                    use_tls="ws"
                fi
                
                echo -e "Enter connection type:
1) tcp  ${purple}[vless , vmess , trojan , ...]${rest}
2) udp  ${purple}[Wireguard , hysteria, tuic , ...]${rest}
3) socks5
4) stdio"
echo ""
read -p "Enter number (default is: 1--> tcp): " choice

                case $choice in
                    1) connection_type="tcp" ;;
                    2) connection_type="udp" ;;
                    3) connection_type="socks5" ;;
                    4) connection_type="stdio" ;;
                    *) connection_type="tcp" ;;
                esac
                read -p "Do you want to use SNI? (yes/no) [default: yes]: " use_sni
                use_sni=${use_sni:-yes}
			    if [ "$use_sni" = "yes" ]; then
			        read -p "Please Enter SNI [default: google.com]: " tls_sni
			        tls_sni=${tls_sni:-google.com}
			        tls_sni_argument="--tls-sni-override $tls_sni"
			    fi

                # Add ?timeout_sec=0 only for UDP
                if [ "$connection_type" = "udp" ]; then
                    timeout_argument="?timeout_sec=0"
                else
                    timeout_argument=""
                fi

                read -p "Do you want to add more ports? (yes/no) [default: no]: " add_port
				add_port=${add_port:-no}
				
				if [ "$add_port" == "yes" ]; then
				    read -p "Enter ports separated by commas (e.g., 2096,8080): " port_list
				    IFS=',' read -ra ports <<< "$port_list"
				
				    for new_port in "${ports[@]}"; do
				        argument+=" -R '$connection_type://[::]:$new_port:localhost:$new_port$timeout_argument'"
				    done
				fi

                argument="client -R '$connection_type://[::]:$config_port:localhost:$config_port$timeout_argument'$argument $use_tls://$foreign_ip:$port $tls_sni_argument"
                break
                ;;
            3)
                echo "Exiting..."
                exit 0 
                ;;
            *)
                echo "Invalid choice. Please Enter a valid number."
                ;;
        esac
    done

    create_service
}

# Create service
create_service() {
    cd /etc/systemd/system

    cat <<EOL>> wstunnel.service
[Unit]
Description=WsTunnel
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/wstunnel $argument

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable wstunnel.service
    sudo systemctl start wstunnel.service
}




install_custom() {
    install_wstunnel
    cd /etc/systemd/system
    echo ""
    read -p "Enter Your custom arguments (Example: wstunnel server wss://[::]:443): " arguments
    
    # Create the custom_tunnel.service file with user input
    cat <<EOL>> wstunnel.service
[Unit]
Description=WsTunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/$arguments

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable wstunnel.service
    sudo systemctl start wstunnel.service
    sleep 1
    check_tunnel_status
}

install() {
    if systemctl is-active --quiet wstunnel.service; then
        echo "The wstunnel service is already installed. and actived."
    else
        install_wstunnel
        get_inputs
    fi
        check_tunnel_status
}

install_reverse() {
    if systemctl is-active --quiet wstunnel.service; then
        echo "The wstunnel service is already installed. and actived."
    else
        install_wstunnel
        get_inputs_Reverse
    fi
        check_tunnel_status
}


#Uninstall 
uninstall() {
    if ! systemctl is-enabled --quiet wstunnel.service > /dev/null 2>&1; then
        echo "WsTunnel is not installed."
        return
    else

	    sudo systemctl stop wstunnel.service
	    sudo systemctl disable wstunnel.service
	    sudo rm /etc/systemd/system/wstunnel.service
	    sudo systemctl daemon-reload
	    sudo rm /usr/local/bin/wstunnel
	
	    echo "WsTunnel has been uninstalled."
    fi
}

check_tunnel_status() {
    # Check the status of the tunnel service
    if systemctl is-active --quiet wstunnel.service; then
        echo -e "${yellow}~~~~~~~~~~~~~~~~~~~~~~~~~~~${rest}"
        echo -e "${cyan}WS Tunnel ==>:${purple}[${green}running ✔${purple}]${rest}"
    else
        echo -e "${cyan}WS Tunnel ==>:${purple}[${red}Not running ✗ ${purple}]${rest}"
    fi
}

#Termux check_dependencies_termux
check_dependencies_termux() {
    local dependencies=("wget" "curl" "tar")
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            echo "${dep} is not installed. Installing..."
            pkg install "${dep}" -y
        fi
    done
}
#Termux install wstunnel
install_ws_termux() {
    if [ -e "wstunnel" ]; then
        echo "wstunnel already exists. Skipping installation."
        echo ""
    else
        pkg update -y
        pkg upgrade -y
        pkg update
        check_dependencies_termux
        latest_version=$(curl -s https://api.github.com/repos/erebe/wstunnel/releases/latest | grep -oP '"tag_name": "\K(.*?)(?=")')
        wstunnel_file="wstunnel_${latest_version//v}_linux_arm64.tar.gz"
        wget "https://github.com/erebe/wstunnel/releases/download/${latest_version}/${wstunnel_file}"
        tar -xvf "$wstunnel_file" > /dev/null
        chmod +x wstunnel
        rm "$wstunnel_file" LICENSE README.md
    fi
    inputs_termux
}

#Termux get inputs
inputs_termux() {
    read -p "Enter foreign IP [External-server]: " foreign_ip
    read -p "Please Enter Your config [vpn] Port: " config_port
    read -p "Please Enter Connection Port (server <--> client) [default, 443]: " port
    port=${port:-443}
    
    read -p "Do you want to use TLS? (yes/no) [default: yes]: " use_tls
    use_tls=${use_tls:-yes}
    use_tls_option="wss" # default to wss
    [ "$use_tls" = "no" ] && use_tls_option="ws"
    
    echo -e "Enter connection type:
1) tcp  ${purple}[vless , vmess , trojan , ...]${rest}
2) udp  ${purple}[Wireguard , hysteria, tuic , ...]${rest}
3) socks5
4) stdio"
echo ""
read -p "Enter number (default is: 1--> tcp): " choice

    case $choice in
        1) connection_type="tcp" ;;
        2) connection_type="udp" ;;
        3) connection_type="socks5" ;;
        4) connection_type="stdio" ;;
        *) connection_type="tcp" ;;
    esac
    
    read -p "Do you want to use SNI? (yes/no) [default: yes]: " use_sni
    use_sni=${use_sni:-yes}
    if [ "$use_sni" = "yes" ]; then
	    read -p "Please Enter SNI [default: google.com]: " tls_sni
	    tls_sni=${tls_sni:-google.com}
	    tls_sni_argument="--tls-sni-override $tls_sni"
	fi
	
     # Add ?timeout_sec=0 only for UDP
    if [ "$connection_type" = "udp" ]; then
        timeout_argument="?timeout_sec=0"
   else
        timeout_argument=""
    fi
    argument="wstunnel client -L $connection_type://[::]:$config_port:localhost:$config_port$timeout_argument $use_tls_option://$foreign_ip:$port $tls_sni_argument"
    echo -e "${yellow}------------Your-Arguments------------${rest}"
    echo ""
    echo "$argument"
    echo -e "${yellow}--------------------------------------${rest}"
    echo ""
   ./$argument
}

main_menu_termux() {
    clear
    echo -e "${purple}-----Ws tunnel in Termux----${rest}"
    echo ""
    echo -e "${purple}1) ${green}Install Ws Tunnel${rest}"
    echo ""
    echo -e "${purple}2) ${cyan}Back to Menu${rest}"
    echo ""
    echo -e "${purple}0) ${red}Exit${rest}"
    echo ""
    read -p "Enter your choice: " choice
    case "$choice" in
        1)
            install_ws_termux
            ;;
        2)
            main_menu
            ;;
        0)
            exit
            ;;
        *)
            echo "Invalid choice. Please select a valid option."
            ;;
    esac
}

# Main menu
main_menu() {
    clear
    echo -e "${white}By --> Peyman * Github.com/Ptechgithub * ${rest}"
    echo -e "${cyan}#===- ${purple}W${yellow}s ${purple}T${yellow}u${purple}n${yellow}n${purple}e${yellow}l ${cyan}-===#${rest}"
    echo ""
    check_tunnel_status
    echo -e "${yellow}~~~~~~~~~~~~~~~~~~~~~~~~~~~${rest}"
    echo -e "${purple}1) ${green}In${cyan}st${green}all${cyan} Ws${green}Tu${cyan}nn${green}el${rest}"
    echo ""
    echo -e "${purple}2) ${cyan}In${green}st${cyan}all Ws${green} Re${cyan}ve${green}rs${cyan}e T${green}un${cyan}ne${green}l${reset}"
    echo ""
    echo -e "${purple}3) ${green}In${cyan}st${green}all C${cyan}us${green}to${cyan}m${reset}"
    echo ""
    echo -e "${purple}4) ${yellow}Un${red}in${yellow}st${red}al${yellow}l w${red}s${yellow}tu${red}nn${yellow}el${reset}"
    echo ""
    echo -e "${purple}5) ${white}In${cyan}sta${white}ll ${cyan}on ${purple}Termux ${yellow}(no root)${rest}"
    echo ""
    echo -e "${purple}0) Exit${rest}"
    echo -e "${yellow}~~~~~~~~~~~~~~~~~~~~~~~~~~~${rest}"
    read -p "Please choose: " choice

    case $choice in
        1)
            install
            ;;
        2)
            install_reverse
            ;;
        3)
            install_custom
            ;;
        4)
            uninstall
            ;;
        5)
            main_menu_termux
            ;;
        0)
            exit
            ;;
        *)
            echo "Invalid choice. Please try again."
            ;;
    esac
}

main_menu