#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <dirent.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/select.h>
#include <sys/ioctl.h>

void csocket_set_block(int socket, int on)
{
    int flags;
    flags = fcntl(socket, F_GETFL, 0);
    if (on == 0)
    {
        fcntl(socket, F_SETFL, flags | O_NONBLOCK);
    }
    else
    {
        flags &= ~ O_NONBLOCK;
        fcntl(socket, F_SETFL, flags);
    }
}

int csocket_connect(const char *host, int port, int timeoutMilliseconds, volatile sig_atomic_t *cancelFlag)
{
    struct sockaddr_in sa;
    struct hostent *hp;
    int sockfd = -1;
    hp = gethostbyname(host);
    if (hp == NULL)
    {
        return -1;
    }

    bcopy((char *)hp->h_addr, (char *)&sa.sin_addr, hp->h_length);
    sa.sin_family = hp->h_addrtype;
    sa.sin_port = htons(port);
    sockfd = socket(hp->h_addrtype, SOCK_STREAM, 0);
    csocket_set_block(sockfd,0);
    int connectResult = connect(sockfd, (struct sockaddr *)&sa, sizeof(sa));
    if (connectResult == 0)
    {
        csocket_set_block(sockfd,1);
        signal(SIGPIPE, SIG_IGN);
        return sockfd;
    }

    int remaining = timeoutMilliseconds;
    int infiniteTimeout = timeoutMilliseconds <= 0;

    fd_set fdwrite;
    struct timeval tvSelect;
    while (1)
    {
        if (cancelFlag && *cancelFlag != 0)
        {
            close(sockfd);
            errno = ECANCELED;
            return -5;
        }

        int waitDuration = 100;
        if (!infiniteTimeout && remaining > 0 && remaining < waitDuration) { waitDuration = remaining; }

        FD_ZERO(&fdwrite);
        FD_SET(sockfd, &fdwrite);
        tvSelect.tv_sec = waitDuration / 1000;
        tvSelect.tv_usec = (waitDuration % 1000) * 1000;

        int retval = select(sockfd + 1, NULL, &fdwrite, NULL, &tvSelect);
        if (retval < 0)
        {
            if (errno == EINTR)
            {
                continue;
            }
            close(sockfd);
            return -2;
        }
        else if (retval == 0)
        {
            if (infiniteTimeout)
            {
                continue;
            }
            remaining -= waitDuration;
            if (remaining <= 0)
            {
                close(sockfd);
                return -3;
            }
            continue;
        }
        else
        {
            int error = 0;
            int errlen = sizeof(error);
            getsockopt(sockfd, SOL_SOCKET, SO_ERROR, &error, (socklen_t *)&errlen);
            if (error != 0)
            {
                close(sockfd);
                return -4;
            }
            csocket_set_block(sockfd,1);
            signal(SIGPIPE, SIG_IGN);
            return sockfd;
        }
    }
}

int csocket_bytes_available(int socketfd)
{
    int count = 0;
    int callResult = ioctl(socketfd, FIONREAD, &count);
    return ( callResult < 0 ) ? callResult : count;
}

int csocket_close(int socketfd)
{
    return close(socketfd);
}
