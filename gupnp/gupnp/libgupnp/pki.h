#ifndef PKI_H_
#define PKI_H_

#include <gnutls/gnutls.h>
#include <stdint.h>
#include <pthread.h>

/* Maximum amount of certificates in one chain/file */
#define MAX_CRT 6

#define GUPNP_CA_CERT_CN      "GUPNP Local CA"

// these error codes are used in libupnp. Here they are defined with extra G in their name
// this is ugly, I know... Just too lazy to modify code to suite better with gupnp
#define GUPNP_E_SUCCESS         0
#define GUPNP_E_FILE_NOT_FOUND  -100
#define GUPNP_E_INVALID_URL     -101
#define GUPNP_E_SOCKET_ERROR    -102
#define GUPNP_E_SOCKET_CONNECT  -103

#define GUPNP_E_SESSION_FAIL    -104

/* default file for CA certificate storing */
#ifndef GUPNP_X509_CA_CERT_FILE
#define GUPNP_X509_CA_CERT_FILE      "gupnpX509-CA-cert.pem"
#endif

/* default file for CA private key storing */
#ifndef GUPNP_X509_CA_PRIVKEY_FILE
#define GUPNP_X509_CA_PRIVKEY_FILE      "gupnpX509-CA-key.pem"
#endif

/* default file for client certificate storing */
#ifndef GUPNP_X509_CLIENT_CERT_FILE
#define GUPNP_X509_CLIENT_CERT_FILE      "gupnpX509.pem"
#endif

/* default file for client private key storing */
#ifndef GUPNP_X509_CLIENT_PRIVKEY_FILE
#define GUPNP_X509_CLIENT_PRIVKEY_FILE      "gupnpX509-client-key.pem"
#endif

/* default file for server certificate storing */
#ifndef GUPNP_X509_SERVER_CERT_FILE
#define GUPNP_X509_SERVER_CERT_FILE      "gupnpX509server.pem"
#endif

/* default file for server private key storing */
#ifndef GUPNP_X509_SERVER_PRIVKEY_FILE
#define GUPNP_X509_SERVER_PRIVKEY_FILE      "gupnpX509-server-key.pem"
#endif

/* Used X.509 certificate version */
#ifndef GUPNP_X509_CERT_VERSION
#define GUPNP_X509_CERT_VERSION           3
#endif

/* default bit size of used modulus in created certificate (key size) */
#ifndef GUPNP_X509_CERT_MODULUS_SIZE
#define GUPNP_X509_CERT_MODULUS_SIZE      2048
#endif

/* how many seconds created certificate should last. Lets use 100 years to make sure that
 * no need for certificate renewal exists
 */
#ifndef GUPNP_X509_CERT_LIFETIME   //(100*365*24*60*60)
#define GUPNP_X509_CERT_LIFETIME   3153600000UL
#endif

/* This tries to solve Year 2038 problem with "too big" unix timestamps, for which
 * gnutls seems to be vulnerable.
 * http://en.wikipedia.org/wiki/Year_2038_problem 
 * 
 * Remove this definition and UPNP_X509_CERT_LIFETIME value will be used for
 * expiration time calculation.
 */
#ifndef GUPNP_X509_CERT_ULTIMATE_EXPIRE_DATE   //Thu Dec 31 23:59:59 UTC 2037
#define GUPNP_X509_CERT_ULTIMATE_EXPIRE_DATE   2145916799
#endif 


#define PSEUDO_RANDOM_UUID_TYPE 0x4
typedef struct {
    uint32_t  time_low;
    uint16_t  time_mid;
    uint16_t time_hi_and_version;
    uint8_t   clock_seq_hi_and_reserved;
    uint8_t   clock_seq_low;
    unsigned char   node[6];
} my_uuid_t;

/************************************************************************
*   Function :  init_crypto_libraries
*
*   Description :   Initialize libgcrypt for gnutls. Not sure should this rather 
*        be done in final program using this UPnP library?
*        Makes gcrypt thread save, and disables usage of blocking /dev/random.
*        Initialize also gnutls.
*
*   Return : int ;
*       0 on succes, gnutls error else
*
*   Note : assumes that libupnp uses pthreads.
************************************************************************/
int init_crypto_libraries(); 


/************************************************************************
*   Function :  init_x509_certificate_credentials
*
*   Parameters :
*       OUT gnutls_certificate_credentials_t *x509_cred     ;  Pointer to gnutls_certificate_credentials_t where certificate credentials are inserted
*       IN const char *directory       ;  Path to directory where files locate or where files are created
*       IN const char *CertFile        ;  Selfsigned certificate file of client
*       IN const char *PrivKeyFile     ;  Private key file of client.
*       IN const char *TrustFile       ;  File containing trusted certificates. (PEM format)
*       IN const char *CRLFile         ;  Certificate revocation list. Untrusted certificates. (PEM format)
*
*   Description :   Init gnutls_certificate_credentials_t structure for use with 
*       input from given parameter files. All files may be NULL
*
*   Return : int ;
*       UPNP or gnutls error code.
*
*   Note :
************************************************************************/
int init_x509_certificate_credentials(gnutls_certificate_credentials_t *x509_cred, const char *directory, const char *CertFile, const char *PrivKeyFile, const char *TrustFile, const char *CRLFile);


/************************************************************************
*   Function :  load_x509_self_signed_certificate
*
*   Parameters :
*       OUT gnutls_x509_crt_t *crt     ;  Pointer to gnutls_x509_crt_t where certificate is created
*       OUT gnutls_x509_privkey_t *key ;  Pointer to gnutls_x509_privkey_t where private key is created
*       IN const char *directory       ;  Path to directory where files locate or where files are created
*       IN const char *certfile        ;  Name of file where certificate is exported in PEM format
*       IN const char *privkeyfile     ;  Name of file where private key is exported in PEM format
*       IN char *CN                    ;  Common Name velue in certificate
*       IN int modulusBits             ;  Size of modulus in certificate
*       IN unsigned long lifetime      ;  How many seconds until certificate will expire. Counted from now.
*       IN int is_client               ;  Is created certificate client certificate. Affects to purpose of certificate.
* 
*   Description :   Create self signed certificate. For this private key is also created.
*           If certfile already contains certificate and privkeyfile contains privatekey,
*           function uses that certificate. If only other is defined, then both will be created.
*
*   Return : int ;
*       UPNP or gnutls error code.
*
*   Note :
************************************************************************/
int load_x509_self_signed_certificate(gnutls_x509_crt_t *crt, unsigned int *crt_size, gnutls_x509_privkey_t *key, const char *directory, const char *certfile, const char *privkeyfile, const char *CN, const int modulusBits, const unsigned long lifetime, int is_client);


/************************************************************************
*   Function :  validate_x509_certificate
*
*   Parameters :
*       IN const gnutls_x509_crt_t *crt  ;  Pointer to certificate which is validated
*       IN const char *hostname          ;  Hostname to compare with certificates subject
*       IN const char *commonname        ;  CN value which is compared with subject CN value of certificate 
* 
*   Description :   Check that given certificate is activated (not before > now), certificate 
*       has not expired (not after < now). If hostname or commonname are defined check that
*       those values match values found from certificate. Hostname check is "a basic implementation 
*       of the matching described in RFC2818 (HTTPS), which takes into account wildcards, and the 
*       DNSName/IPAddress subject alternative name PKIX extension." (gnutls)
*       Commonname check just checks if commonname value equals CN found from certificates subject.
*
*   Return : int ;
*       UPNP or gnutls error code.
*
*   Note :
************************************************************************/
int validate_x509_certificate(const gnutls_x509_crt_t *crt, const char *hostname, const char *commonname);


/************************************************************************
*   Function :  get_peer_certificate
*
*   Parameters :
*       IN gnutls_session_t session  ;  SSL session
*       OUT unsigned char *data      ;  Certificate is returned in DER format here
*       OUT int *data_size           ;  Pointer to integer which represents length of certificate 
*       OUT char **CN                ;  Pointer to string where Common Name value from peer certificate is put. If NULL this is ignored. 
* 
*   Description :   Export peer certificate to given parameter. When calling this
*       data must have enough memory allocated and data_size must contain info
*       how much data has space.
*
*   Return : int ;
*       UPNP or gnutls error code.
*
*   Note :
************************************************************************/
int get_peer_certificate(gnutls_session_t session, unsigned char *data, int *data_size, char **CN);

/**
 * Create uuid string from given data. (In this case data is hash created from certificate)
 * 
 * "The CP Identity is a UUID derived from the first 128 bits of the SHA-256 hash of the 
 * CP’s X.509 certificate in accordance with the procedure given in Section 4.4 and Appendix A 
 * of RFC 4122."
 * 
 * @param uuid_str Pointer to string where uuid is created. User must release this with free()
 * @param uuid_bin Created uuid in binary form before it is converted to its string presentation
 * @param uuid_size Pointer to length of uuid_bin. (16 bytes)
 * @param hash Input data from which uuid is created
 * @param hashLen Length of input data. Or how much of it is used.
 * @return void
 */
void createUuidFromData(char **uuid_str, unsigned char **uuid_bin, size_t *uuid_bin_size, unsigned char *hash, int hashLen);

#endif /*PKI_H_*/
