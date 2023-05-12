# Installing the Phase Two library in an unpacked Keycloak (aka "bare metal installations")

This README covers how to deploy a Keycloak instance on bare metal

### Installation
Make sure you have at least JDK 11 or higher installed

Download [Keycloak](https://www.keycloak.org/downloads)

Extract the zip or gz archive

### Configuration

Keycloak can be configured easily through command-line parameters, environment variables or config files.
We will use config files for our configuration. The config file `keycloak.conf` can be found in the `conf` folder in your keycloak installation
> Please refer to the official [Keycloak configuration doc](https://www.keycloak.org/server/configuration) for further information

### Keycloak-orgs
In the next step we will add the plugins needed for the organizations extension which is used to support multi tenancy

Clone this repository and open it in your terminal

Set your git HEAD to the last commit regarding your needed keycloak version
>  To do this use the command `git checkout <commit_id>`

The Dockerfile always specifies the used Keycloak version and commits bumping up that version have the bump up mentioned in their title. Use the [commit history](https://github.com/p2-inc/phasetwo-containers/commits/main/Dockerfile) of this file to figure out which commit you need

Change your directory to the libs folder

Execute the `mvn package` command

Copy the jar files in the ext folder and the jar files in the `target/<artifact-id>-<version>` into the providers folder in your keycloak installation
> The values of `artifact-id` and `version` can be found in the pom.xml file located in the libs folder

Change your directory to your keycloak installation

Execute the command 
```
bin/kc.sh --verbose build --spi-email-template-provider=freemarker-plus-mustache --spi-email-template-freemarker-plus-mustache-enabled=true --spi-theme-cache-themes=false
```
> Please check if this command changed in the [Dockerfile](../Dockerfile)<br>
> On Windows please use kc.bat instead of kc.sh everything else remains the same

### Deployment

Run the command `bin/kc.bat start-dev`

Congrats! Your Keycloak server should be running now on address [localhost:8080](http://localhost:8080)
> If you configured a different port, hostname, http-relative-path, etc. this could be different for you
