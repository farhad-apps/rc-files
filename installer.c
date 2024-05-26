#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdarg.h> 
#include <ctype.h>

int file_exists(const char* file) {
    if (access(file, F_OK) == 0) {
        return 1;
    } else {
        return 0;
    }
}

char* execute_command(const char* format, ...) {
    char* result = NULL;
    va_list args;
    va_start(args, format);
    char command[256];
    vsnprintf(command, sizeof(command), format, args);
    va_end(args); 

    FILE* pipe = popen(command, "r");
    if (pipe != NULL) {
        char buffer[128];
        size_t size = 0;
        size_t capacity = 128;
        result = malloc(capacity);

        while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
            size_t length = strlen(buffer);
            if (size + length >= capacity) {
                capacity *= 2;
                result = realloc(result, capacity);
            }
            memcpy(result + size, buffer, length);
            size += length;
        }
        result[size] = '\0';

        pclose(pipe);
    }
    return result;
}

void replace_strings(char* script, const char* search, const char* replace) {
    size_t search_len = strlen(search);
    size_t replace_len = strlen(replace);
    char* pos = script;
    while ((pos = strstr(pos, search)) != NULL) {
        memmove(pos + replace_len, pos + search_len, strlen(pos + search_len) + 1);
        memcpy(pos, replace, replace_len);
        pos += replace_len;
    }
    
}

char* trim_string(char* str) {
    char* end;
    while (isspace((unsigned char)*str) || *str == '\n') {
        str++;
    }
    if (*str == 0) { 
        return str;
    }
    end = str + strlen(str) - 1;
    while (end > str && (isspace((unsigned char)*end) || *end == '\n')) {
        end--;
    }
    *(end + 1) = '\0';
    return str;
}


char* get_configs(const char* path, const char* configs_file_path) {
    if (!file_exists(configs_file_path)) {
        printf("config file does not exist.\n");
        exit(1);
    }

    char jq_query[256];
    snprintf(jq_query, sizeof(jq_query), ".%s", path);

    char* result = execute_command("jq --raw-output '%s' %s", jq_query, configs_file_path);

    return trim_string(result);
}

void setup_ssh(const char* configs_file_path) {
    char* ssh_port = get_configs("servers_ssh.port", configs_file_path);
    char* udp_port = get_configs("servers_ssh.udp_port", configs_file_path);
    char* api_token = get_configs("api_token", configs_file_path);
    char* api_url = get_configs("api_url", configs_file_path);

    if (ssh_port != NULL && strcmp(ssh_port, "null") != 0) {
        const char* ssh_file_url = "https://raw.githubusercontent.com/farhad-apps/rc-files/main/setup-ssh.sh";
        char* ssh_script = execute_command("curl -s %s", ssh_file_url);

        replace_strings(ssh_script, "{apiToken}", api_token);
        replace_strings(ssh_script, "{apiUrl}", api_url);
        replace_strings(ssh_script, "{sshPort}", ssh_port);
        replace_strings(ssh_script, "{udpPort}", udp_port);

        system(ssh_script);
        free(ssh_script);
    }

    free(ssh_port);
    free(udp_port);
    free(api_token);
    free(api_url);
}

void setup_openvpn(const char* configs_file_path) {
    char* ovpn_port = get_configs("servers_openvpn.port", configs_file_path);
    char* ovpn_domain = get_configs("servers_openvpn.domain", configs_file_path);
    char* api_token = get_configs("api_token", configs_file_path);
    char* api_url = get_configs("api_url", configs_file_path);

    if (ovpn_port != NULL && strcmp(ovpn_port, "null") != 0) {
        const char* ovpn_file_url = "https://raw.githubusercontent.com/farhad-apps/rc-files/main/setup-openvpn.sh";
        char* ovpn_script = execute_command("curl -s %s", ovpn_file_url);

        replace_strings(ovpn_script, "{apiToken}", api_token);
        replace_strings(ovpn_script, "{apiUrl}", api_url);
        replace_strings(ovpn_script, "{ovpnPort}", ovpn_port);
        replace_strings(ovpn_script, "{ovpnDomain}", ovpn_domain);

        system(ovpn_script);
        free(ovpn_script);
    }

    free(ovpn_port);
    free(ovpn_domain);
    free(api_token);
    free(api_url);
}

void setup_v2ray(const char* configs_file_path) {
    char* vless_tcp_port = get_configs("servers_v2ray.vless_tcp_port", configs_file_path);
    char* vmess_tcp_port = get_configs("servers_v2ray.vmess_tcp_port", configs_file_path);
    char* api_token = get_configs("api_token", configs_file_path);
    char* api_url = get_configs("api_url", configs_file_path);

    if (vless_tcp_port != NULL && strcmp(vless_tcp_port, "null") != 0) {
        if (vmess_tcp_port != NULL && strcmp(vmess_tcp_port, "null") != 0) {
            const char* v2ray_file_url = "https://raw.githubusercontent.com/farhad-apps/rc-files/main/setup-v2ray.sh";
            char* v2ray_script = execute_command("curl -s %s", v2ray_file_url);

            replace_strings(v2ray_script, "{apiToken}", api_token);
            replace_strings(v2ray_script, "{apiUrl}", api_url);
            replace_strings(v2ray_script, "{vlessTcpPort}", vless_tcp_port);
            replace_strings(v2ray_script, "{vmessTcpPort}", vmess_tcp_port);

            system(v2ray_script);
            free(v2ray_script);
        }
    }

    free(vless_tcp_port);
    free(vmess_tcp_port);
    free(api_token);
    free(api_url);
}

void setup_main(const char* configs_file_path) {
    char* api_token = get_configs("api_token", configs_file_path);
    char* api_url = get_configs("api_url", configs_file_path);
    const char* main_file_url = "https://raw.githubusercontent.com/farhad-apps/rc-files/main/main-setup.sh";
    char* main_content = execute_command("curl -s %s", main_file_url);

    replace_strings(main_content, "{apiToken}", api_token);
    replace_strings(main_content, "{apiUrl}", api_url);
     
    system(main_content);
    free(main_content);
    free(api_token);
    free(api_url);
}

void update_rocket_app(const char* configs_file_path) {
    char* api_token = get_configs("api_token", configs_file_path);
    char* api_url = get_configs("api_url", configs_file_path);
    const char* file_url = "https://raw.githubusercontent.com/farhad-apps/rc-files/main/rocket-app.js";
    const char* file_path = "/var/rocket-ssh/rocket-app.js";

    execute_command("curl -s -o %s %s", file_path, file_url);

    if (file_exists(file_path)) {
        char* sed_command = malloc(strlen(api_token) + strlen(api_url) + strlen(file_path) + 128);
        sprintf(sed_command, "sed -i 's|{rapiToken}|%s|g' '%s'", api_token, file_path);
        system(sed_command);
        sprintf(sed_command, "sed -i 's|{rapiUrl}|%s|g' '%s'", api_url, file_path);
        system(sed_command);
        free(sed_command);
    }

    system("supervisorctl restart rocketApp");
    free(api_token);
    free(api_url);
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        printf("No parameters provided. Please provide a parameter.\n");
        return 1;
    }

    system("sudo apt update");
    system("sudo apt-get install -y wget curl jq");

    const char* action = argv[1];
    const char* configs_file_path = "/var/rocket-ssh/configs.json";

    if (strcmp(action, "default-setup") == 0) {
        setup_main(configs_file_path);
    } else if (strcmp(action, "setup-ssh") == 0) {
        setup_ssh(configs_file_path);
    } else if (strcmp(action, "setup-openvpn") == 0) {
        setup_openvpn(configs_file_path);
    } else if (strcmp(action, "setup-v2ray") == 0) {
        setup_v2ray(configs_file_path);
    } else if (strcmp(action, "setup-all") == 0) {
        setup_ssh(configs_file_path);
        setup_openvpn(configs_file_path);
        setup_v2ray(configs_file_path);
    } else if (strcmp(action, "update-rocket-app") == 0) {
        update_rocket_app(configs_file_path);
    } else {
        printf("Unknown parameter: %s\n", action);
        return 1;
    }

    return 0;
}
