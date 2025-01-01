#include <security/pam_modules.h>
#include <security/pam_ext.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <time.h>
#include <curl/curl.h>

// Define the global variables
#define API_TOKEN "{api_token}"
#define API_BASE_URL "{api_url}"
#define USER_SESSION_KEY "USER_SESSION_CODE"

// Function to execute a shell command and capture its output
char* get_server_ip() {
    FILE *fp;
    char buffer[128];
    char *server_ip = NULL;

    // Execute the command
    fp = popen("ip route get 1.1.1.1 | grep -oP 'src \\K[^ ]+'", "r");
    if (fp == NULL) {
        syslog(LOG_ERR, "Failed to run command to get server IP");
        return NULL;
    }

    // Read the output
    if (fgets(buffer, sizeof(buffer), fp) != NULL) {
        size_t len = strlen(buffer);
        if (len > 0 && buffer[len - 1] == '\n') {
            buffer[len - 1] = '\0'; // Remove newline
        }
        server_ip = strdup(buffer); // Allocate memory for the IP string
    }

    pclose(fp);
    return server_ip;
}

// Function to generate a unique code (unchanged)
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

// Updated API calls with server IP
PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    const char *username, *user_ip;
    int UPID;
    pam_get_user(pamh, &username, NULL);
    pam_get_item(pamh, PAM_RHOST, (const void **)&user_ip);

    if (strcmp(username, "root") == 0) {
        return PAM_SUCCESS;
    }

    char *session_key = generate_unique_code(username);
    setenv(USER_SESSION_KEY, session_key, 1);

    char *server_ip = get_server_ip();
    if (!server_ip) {
        syslog(LOG_ERR, "Unable to retrieve server IP");
        return PAM_AUTH_ERR;
    }

    CURL *curl = curl_easy_init();
    if (!curl) {
        syslog(LOG_ERR, "Failed to initialize libcurl");
        free(server_ip);
        return PAM_AUTH_ERR;
    }

    UPID = getpid();
    char api_url[512];
    snprintf(api_url, sizeof(api_url), "%s/ssh/ulogin?token=%s&username=%s&session_key=%s&user_ip=%s&server_ip=%s&pid=%d",
             API_BASE_URL, API_TOKEN, username, session_key, user_ip, server_ip, UPID);

    syslog(LOG_ERR, "API: %s", api_url);
    curl_easy_setopt(curl, CURLOPT_URL, api_url);

    CURLcode res = curl_easy_perform(curl);
    free(server_ip);
    if (res == CURLE_OK) {
        long http_code = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
        if (http_code == 200) {
            curl_easy_cleanup(curl);
            return PAM_SUCCESS;
        }
    }

    syslog(LOG_ERR, "API call for user '%s' failed: %s", username, curl_easy_strerror(res));
    curl_easy_cleanup(curl);
    return PAM_AUTH_ERR;
}

PAM_EXTERN int pam_sm_close_session(pam_handle_t *pamh, int flags, int argc, const char **argv) {
    const char *username, *user_ip;
    int UPID;
    pam_get_user(pamh, &username, NULL);
    pam_get_item(pamh, PAM_RHOST, (const void **)&user_ip);

    if (strcmp(username, "root") == 0) {
        return PAM_SUCCESS;
    }

    const char *session_key = getenv(USER_SESSION_KEY);
    char *server_ip = get_server_ip();
    if (!server_ip) {
        syslog(LOG_ERR, "Unable to retrieve server IP");
        return PAM_SUCCESS;
    }

    CURL *curl = curl_easy_init();
    if (!curl) {
        syslog(LOG_ERR, "Failed to initialize libcurl");
        free(server_ip);
        return PAM_SUCCESS;
    }

    UPID = getpid();
    char api_url[512];
    snprintf(api_url, sizeof(api_url), "%s/ssh/ulogout?token=%s&username=%s&session_key=%s&user_ip=%s&server_ip=%s&pid=%d",
             API_BASE_URL, API_TOKEN, username, session_key, user_ip, server_ip, UPID);

    syslog(LOG_ERR, "API: %s", api_url);
    curl_easy_setopt(curl, CURLOPT_URL, api_url);

    CURLcode res = curl_easy_perform(curl);
    free(server_ip);
    if (res != CURLE_OK) {
        syslog(LOG_ERR, "API call for user '%s' on logout failed: %s", username, curl_easy_strerror(res));
    }

    curl_easy_cleanup(curl);
    return PAM_SUCCESS;
}
