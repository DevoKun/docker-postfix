docker postfix
==============

* Run postfix with smtp authentication (sasldb) in a docker container.
* OpenDKIM support is optional.
* TLS certs can be provided by the user or a default _(self-signed)_ cert will be generated using [mkcert](https://github.com/FiloSottile/mkcert).
* Will optionally relay mail through **Amazon SES**.




## Pull the Image

```bash
docker pull devokun/postfix
```

## Usage

* The `MAILDOMAIN` environment variable is for the domain which the postfix container will handle. When using Amazon SES as an upstream relay, the `MAILDOMAIN` environment variable **MUST** match the authorized domain in SES.
* The `MYHOSTNAME` environment variable should match the DNS entry that the clients will connect to. `MYHOSTNAME` should eb different than the upstream Amazon SES relay or else the container may attempt to deliver the mail locally inside the container.

### Create postfix container with smtp authentication

* The username and password for the connecting client is set via the `SMTP_USER` environment variable.
* Set a single user: `SMTP_USER=username:password`
* Set multiple users: `SMTP_USER=user1:pwd1,user2:pwd2,...,userN:pwdN`


```bash
docker run \
  -p 25:25 -p 587:587 \
	-e MAILDOMAIN=mydomain.local \
	-e MYHOSTNAME=smtprelay.mydomain.local \
	-e SMTP_USER=username:password \
	--name postfix \
	-d \
	devokun/postfix
```



### Enable OpenDKIM

* The container will look for DomainKeys with a `.private` extension in `/etc/opendkim/domainkeys` on startup.
* If the keys are found, then OpenDKIM will be enabled.


```bash
docker run -p 25:25 -p 587:587 \
	-e MAILDOMAIN=mydomain.local \
	-e MYHOSTNAME=smtprelay.mydomain.local \
	-e SMTP_USER=user:pwd \
	-v $(pwd)/domainkeys:/etc/opendkim/domainkeys \
	--name postfix \
	-d \
	devokun/postfix
```

## Use custom TLS Certs

* The container will look for SSL certs with a `.key` and `.crt` extension in `/etc/postfix/certs` on startup.
* If no certs are found, then the container will use [mkcert](https://github.com/FiloSottile/mkcert) to generate a cert that matches the `MYHOSTNAME` environment variable.


```bash
docker run -p 587:587 \
	-e MAILDOMAIN=mydomain.local \
	-e MYHOSTNAME=smtprelay.mydomain.local \
	-e SMTP_USER=user:pwd \
	-v $(pwd)/certs:/etc/postfix/certs \
	--name postfix \
	-d \
	devokun/postfix
```


## Reference

* Based on [CatAtNight/Postfix](https://github.com/catatnight/docker-postfix) Docker Image.
