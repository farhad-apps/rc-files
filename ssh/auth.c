#include <security/pam_modules.h>
#include <security/pam_ext.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <time.h>
#include <curl/curl.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

// Define the global variables
#define API_TOKEN "{api_token}"
#define API_BASE_URL "{api_url}"
#define USER_SESSION_KEY "USER_SESSION_CODE"

// Function to generate a unique code (you can customize this)
char* generate_unique_code(const char* username) {
    srand(time(NULL));

    const char charset[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
    const int code_length = 10;

    char* unique_code = (char*)malloc((code_length + 1) * sizeof(char));

    if (unique_code != NULL) {
        for (int i = 0; i < code_length; i++) {
            int index = rand() % (sizeof(charset) - 1);
            unique_code[i] = charset[index];
        }
        unique_code[code_length] = '\0';
    }

    return unique_code;
}

// Function to get the main IP address
char *get_main_ip() {
    int sock;
    struct sockaddr_in dest_addr;
    static char ip[INET_ADDRSTRLEN];

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        syslog(LOG_ERR, "Failed to create socket to get main IP");
        return NULL;
    }

    memset(&dest_addr, 0, sizeof(dest_addr));
    dest_addr.sin_family = AF_INET;
    dest_addr.sin_port = htons(53);
    inet_pton(AF_INET, "1.1.1.1", &dest_addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&dest_addr, sizeof(dest_addr)) < 0) {
        syslog(LOG_ERR, "Failed to connect socket to get main IP");
        close(sock);
        return NULL;
    }

    struct sockaddr_in local_addr;
    socklen_t addr_len = sizeof(local_addr);
    if (getsockname(sock, (struct sockaddr *)&local_addr, &addr_len) < 0) {
        syslog(LOG_ERR, "Failed to get local IP address");
        close(sock);
        return NULL;
    }

    inet_ntop(AF_INET, &local_addr.sin_addr, ip, sizeof(ip));
    close(sock);
    return ip;
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    const char *username;
    int UPID;
    pam_get_user(pamh, &username, NULL);

    const char *user_ip;
    pam_get_item(pamh, PAM_RHOST, (const void **)&user_ip);

    if (strcmp(username, "root") == 0) {
        return PAM_SUCCESS;
    }

    char *session_key = generate_unique_code(username);
    setenv(USER_SESSION_KEY, session_key, 1);

    CURL *curl = curl_easy_init();
    if (!curl) {
        syslog(LOG_ERR, "Failed to initialize libcurl");
        return PAM_AUTH_ERR;
    }

    UPID = getpid();

    // Retrieve the server's main IP address
    char *server_ip = get_main_ip();
    if (!server_ip) {
        syslog(LOG_ERR, "Failed to retrieve main server IP");
        curl_easy_cleanup(curl);
        return PAM_AUTH_ERR;
    }

    char api_url[512];
    snprintf(api_url, sizeof(api_url), "%s/ssh/ulogin?token=%s&username=%s&session_key=%s&user_ip=%s&pid=%d&server_ip=%s",
             API_BASE_URL, API_TOKEN, username, session_key, user_ip, UPID, server_ip);

    syslog(LOG_ERR, "API: %s", api_url);

    curl_easy_setopt(curl, CURLOPT_URL, api_url);

    CURLcode res = curl_easy_perform(curl);

    if (res == CURLE_OK) {
        long http_code = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);

        if (http_code == 200) {
            curl_easy_cleanup(curl);
            return PAM_SUCCESS;
        }
    }

    syslog(LOG_ERR, "API call failed for user '%s': %s", username, curl_easy_strerror(res));
    curl_easy_cleanup(curl);
    return PAM_AUTH_ERR;
}

PAM_EXTERN int pam_sm_open_session(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    const char *username;
    pam_get_user(pamh, &username, NULL);

    const char *session_key = getenv(USER_SESSION_KEY);

    if (session_key != NULL) {
        syslog(LOG_ERR, "Open session - username: %s, session key: %s", username, session_key);
    }

    return PAM_SUCCESS;
}

PAM_EXTERN int pam_sm_close_session(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    const char *username;
    int UPID;
    pam_get_user(pamh, &username, NULL);

    if (strcmp(username, "root") == 0) {
        return PAM_SUCCESS;
    }

    const char *user_ip;
    pam_get_item(pamh, PAM_RHOST, (const void **)&user_ip);

    const char *session_key = getenv(USER_SESSION_KEY);

    CURL *curl = curl_easy_init();
    if (!curl) {
        syslog(LOG_ERR, "Failed to initialize libcurl");
        return PAM_SUCCESS;
    }

    UPID = getpid();

    char *server_ip = get_main_ip();
    if (!server_ip) {
        syslog(LOG_ERR, "Failed to retrieve main server IP");
        curl_easy_cleanup(curl);
        return PAM_SUCCESS;
    }

    char api_url[512];
    snprintf(api_url, sizeof(api_url), "%s/ssh/ulogout?token=%s&username=%s&session_key=%s&user_ip=%s&pid=%d&server_ip=%s",
             API_BASE_URL, API_TOKEN, username, session_key, user_ip, UPID, server_ip);

    syslog(LOG_ERR, "API: %s", api_url);

    curl_easy_setopt(curl, CURLOPT_URL, api_url);

    CURLcode res = curl_easy_perform(curl);

    if (res != CURLE_OK) {
        syslog(LOG_ERR, "API call failed for user '%s': %s", username, curl_easy_strerror(res));
    }

    curl_easy_cleanup(curl);
    return PAM_SUCCESS;
}
