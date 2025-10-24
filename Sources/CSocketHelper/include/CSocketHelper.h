 #include <signal.h>
int csocket_connect(const char *host, int port, int timeoutMilliseconds, volatile sig_atomic_t *cancelFlag);
int csocket_close(int socketfd);
