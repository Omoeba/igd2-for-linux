#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <syslog.h>
#include <arpa/inet.h>
#include <linux/sockios.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <upnp/upnp.h>
#include "globals.h"


static int get_sockfd(void)
{
    static int sockfd = -1;

    if (sockfd == -1)
    {
        if ((sockfd = socket(PF_INET, SOCK_RAW, IPPROTO_RAW)) == -1)
        {
            perror("user: socket creating failed");
            return (-1);
        }
    }
    return sockfd;
}

/**
 * Get MAC address of given network interface.
 *
 * @param address MAC address is wrote into this.
 * @param ifname Interface name.
 * @return 1 if success, 0 if failure. MAC address is returned in address parameter.
 */
int GetMACAddressStr(unsigned char *address, int addressSize, char *ifname)
{
    struct ifreq ifr;
    int fd;
    int succeeded = 0;

    fd = get_sockfd();
    if (fd >= 0 )
    {
        strncpy(ifr.ifr_name, ifname, IFNAMSIZ);
        if (ioctl(fd, SIOCGIFHWADDR, &ifr) == 0)
        {    
            memcpy(address, ifr.ifr_hwaddr.sa_data, addressSize);
            succeeded = 1;
        }
        else
        {
            syslog(LOG_ERR, "Failure obtaining MAC address of interface %s", ifname);
            succeeded = 0;
        }
    }
    return succeeded;
}

/**
 * Get IP address assigned for given network interface.
 *
 * @param address IP address is wrote into this.
 * @param ifname Interface name.
 * @return 1 if success, 0 if failure. IP address is returned in address parameter.
 */
int GetIpAddressStr(char *address, char *ifname)
{
    struct ifreq ifr;
    struct sockaddr_in *saddr;
    int fd;
    int succeeded = 0;

    fd = get_sockfd();
    if (fd >= 0 )
    {
        strncpy(ifr.ifr_name, ifname, IFNAMSIZ);
        ifr.ifr_addr.sa_family = AF_INET;
        if (ioctl(fd, SIOCGIFADDR, &ifr) == 0)
        {
            saddr = (struct sockaddr_in *)&ifr.ifr_addr;
            strcpy(address,inet_ntoa(saddr->sin_addr));
            succeeded = 1;
        }
        else
        {
            syslog(LOG_ERR, "Failure obtaining ip address of interface %s", ifname);
            succeeded = 0;
        }
    }
    return succeeded;
}

/**
 * Get connection status string used as ConnectionStatus state variable.
 * If interface has IP, status id connected. Else disconnected
 * There are also manually adjusted states Unconfigured, Connecting and Disconnecting!
 *
 * @param conStatus Connection status string is written in this.
 * @param ifname Interface name.
 * @return 1 if success, 0 if failure. Connection status is returned in conStatus parameter.
 */
int GetConnectionStatus(char *conStatus, char *ifname)
{
    char tmp[INET_ADDRSTRLEN];
    int status = GetIpAddressStr(tmp, ifname);

    if (status == 1)
        strcpy(conStatus,"Connected");
    else
        strcpy(conStatus,"Disconnected");

    return status;
}

/**
 * Check if IP of control point is same as internal client address in portmapping.
 * 
 * @param ICAddresscon IP of Internalclient in portmapping.
 * @param in_ad IP of control point.
 * @return 1 if match, 0 else.
 */
int ControlPointIP_equals_InternalClientIP(char *ICAddress, struct in_addr *in_ad)
{
    char cpAddress[INET_ADDRSTRLEN];
    int result;
    int succeeded = 0;

    inet_ntop(AF_INET, in_ad, cpAddress, INET_ADDRSTRLEN);

    result = strcmp(ICAddress, cpAddress);

    // Check the compare result InternalClient IP address is same than Control Point
    if (result == 0)
    {
        succeeded = 1;
    }
    else
    {
        syslog(LOG_ERR, "CP and InternalClient IP addresees won't match:  %s %s", ICAddress, cpAddress);
        succeeded = 0;
    }

    return succeeded;
}

void trace(int debuglevel, const char *format, ...)
{
    va_list ap;
    va_start(ap,format);
    if (g_vars.debug>=debuglevel)
    {
        vsyslog(LOG_DEBUG,format,ap);
    }
    va_end(ap);
}

/**
 * Check if parameter string has a wildcard character '*', or if string is '0' which might be used as wildcard
 * for port number, or if string is empty string which wildcard form of ip addresses.
 * 
 * @param str String to check.
 * @return 1 if found, 0 else.
 */
int checkForWildCard(const char *str)
{
    int retVal = 0;

    if ((strchr(str, '*') != NULL) || (strcmp(str,"0") == 0) || (strcmp(str,"") == 0))
	   retVal = 1;

    return retVal;
}

/**
 * Add error data to event structure used by libupnp for creating response for action request message.
 * 
 * @param ca_event Response structure used for response.
 * @param errorCode Error code number.
 * @param message Error message string.
 */
void addErrorData(struct Upnp_Action_Request *ca_event, int errorCode, char* message)
{
    ca_event->ErrCode = errorCode;
    strcpy(ca_event->ErrStr, message);
    ca_event->ActionResult = NULL;
}

/**
 * Resolve if given string is acceptable as boolean value used in upnp action request messages.
 * 'yes', 'true' and '1' currently acceptable values.
 * 
 * @param value String to check.
 * @return 1 if true, 0 else.
 */
int resolveBoolean(char *value)
{
    if ( strcasecmp(value, "yes") == 0 ||
         strcasecmp(value, "true") == 0 ||
         strcasecmp(value, "1") == 0 )
    {
        return 1;
    }

    return 0;
}

void ParseXMLResponse(struct Upnp_Action_Request *ca_event, const char *result_str)
{
    IXML_Document *result = NULL;

    if ((result = ixmlParseBuffer(result_str)) != NULL)
    {
        ca_event->ActionResult = result;
        ca_event->ErrCode = UPNP_E_SUCCESS;
    }
    else
    {
        trace(1, "Error parsing response to %s: %s", ca_event->ActionName, result_str);
        ca_event->ActionResult = NULL;
        ca_event->ErrCode = 402;
    }
}

/**
 * Get document item which is at position index in nodelist (all nodes with same name item).
 * Index 0 means first, 1 second, etc.
 * 
 * @param doc XML document where item is fetched.
 * @param item Name of xml-node to fetch.
 * @param index Which one of nodes with same name is selected.
 * @return Value of desired node.
 */
char* GetDocumentItem(IXML_Document * doc, const char *item, int index)
{
    IXML_NodeList *nodeList = NULL;
    IXML_Node *textNode = NULL;
    IXML_Node *tmpNode = NULL;

    //fprintf(stderr,"%s\n",ixmlPrintDocument(doc)); //DEBUG

    char *ret = NULL;

    nodeList = ixmlDocument_getElementsByTagName( doc, ( char * )item );

    if ( nodeList )
    {
        if ( ( tmpNode = ixmlNodeList_item( nodeList, index ) ) )
        {
            textNode = ixmlNode_getFirstChild( tmpNode );
            if (textNode != NULL)
            {
                ret = strdup( ixmlNode_getNodeValue( textNode ) );
            }
            // if desired node exist, but textNode is NULL, then value of node propably is ""
            else
                ret = strdup("");
        }
    }

    if ( nodeList )
        ixmlNodeList_free( nodeList );
    return ret;
}

/**
 * Get first document item in nodelist with name given in item parameter.
 * 
 * @param doc XML document where item is fetched.
 * @param item Name of xml-node to fetch.
 * @return Value of desired node.
 */
char* GetFirstDocumentItem( IN IXML_Document * doc,
                            IN const char *item )
{
    return GetDocumentItem(doc,item,0);
}

/**
 * Resolve up/down status of given network interface and insert it into given string.
 * Status is up if interface is listed in /proc/net/dev_mcast -file, else down.
 * 
 * @param ethLinkStatus Pointer to string where status is wrote.
 * @param iface Network interface name.
 * @return 0 if status is up, 1 if down or failed to open dev_mcast file.
 */
int setEthernetLinkStatus(char *ethLinkStatus, char *iface)
{
    FILE *fp;
    char str[60];

    // check from dev_mcast if interface is up (up if listed in file)
    // This could be done "finer" with reading registers from socket. Check from ifconfig.c or mii-tool.c. Do if nothing better to do.
    if((fp = fopen("/proc/net/dev_mcast", "r"))==NULL) {
        syslog(LOG_ERR, "Cannot open /proc/net/dev_mcast");
        return 1;
    }

    while(!feof(fp)) {
        if(fgets(str,60,fp) && strstr(str,iface))
        {
            strcpy(ethLinkStatus,"Up");
            fclose(fp);
            return 0;
        }
    }

    fclose(fp);
    strcpy(ethLinkStatus,"Down");
    return 1;
}

/**
 * Read integer value from given file. File should only contain this one numerical value.
 * 
 * @param file Name of file to read.
 * @param iface Network interface name.
 * @return Value read from file. -1 if fails to open file, -2 if no value found from file.
 */ 
int readIntFromFile(char *file)
{
    FILE *fp;
    int value = -1;

    trace(3,"Read integer value from %s", file);

    if((fp = fopen(file, "r"))==NULL) {
        return -1;
    }

    while(!feof(fp)) {
        fscanf(fp,"%d", &value);
        if (value > -1)
        {
            fclose(fp);
            return value;
        }
    }
    fclose(fp);
    return -2;
}

/**
 * Kill DHCP client. After killing check that IP of iface has been released.
 * 
 * @param iface Network interface name.
 * @return 1 if DHCP client is killed and IP released, 0 else.
 */ 
int killDHCPClient(char *iface)
{
    char tmp[30];
    int pid;

    trace(2,"Killing DHCP client...");
    snprintf(tmp, 50, "/var/run/%s.pid", iface);
    pid = readIntFromFile(tmp);
    if (pid > -1)
    {
        snprintf(tmp, 30, "kill %d", pid);
        trace(3,"system(%s)",tmp);
        system(tmp);
    }
    else
    {
        // brute force
        trace(3,"No PID file available for %s of %s",g_vars.dhcpc,iface);
        snprintf(tmp, 30, "killall %s", g_vars.dhcpc);
        trace(3,"system(%s)",tmp);
        system(tmp);
    }

    sleep(2); // wait that IP is released

    if (!GetIpAddressStr(tmp, iface))
    {
        trace(3,"Success IP of %s is released",iface);
        return 1;
    }
    else
    {
        trace(3,"Failure IP of %s: %s",iface,tmp);
        return 0;
    }
}

/**
 * Start DHCP client. After starting check that iface has IP.
 * 
 * @param iface Network interface name.
 * @return 1 if DHCP client is started and iface has IP, 0 else.
 */ 
int startDHCPClient(char *iface)
{
    char tmp[50];

    trace(2,"Starting DHCP client...");
    snprintf(tmp, 50, "%s -t 0 -i %s -R", g_vars.dhcpc, iface);
    trace(3,"system(%s)",tmp);
    system(tmp);

    sleep(2); // wait that IP is acquired

    if (GetIpAddressStr(tmp, iface))
    {
        trace(3,"Success IP of %s: %s",iface,tmp);
        return 1;
    }
    else
    {
        trace(3,"Failure %s doens't have IP",iface);
        return 0;
    }
}

/**
 * Release IP address of given interface.
 *
 * @param iface Network interface name.
 * @return 1 if iface doesn't have IP, 0 else.
 */
int releaseIP(char *iface)
{
    char tmp[INET6_ADDRSTRLEN];
    int success = 0;

    // check does IP exist
    if (!GetIpAddressStr(tmp, iface))
        return 1;

    // kill already running udhcpc-client for given iface and check if IP was released
    if (killDHCPClient(iface))
        success = 1; //OK
    else
    {
        // start udhcpc-clientdaemon with parameter -R which will release IP after quiting daemon
        startDHCPClient(iface);

        // then kill udhcpc-client running. Now there shouldn't be IP anymore.
        if(killDHCPClient(iface))
            success = 1;
    }
    return success;
}
