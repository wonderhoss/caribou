# Caribou - An Extensible AWS deployment framework

##Requirements
Gems:
* AWS SDK for Ruby v2
* NetAddr
* net-ssh
* net-scp
* terminal-table (https://github.com/tj/terminal-table)

* Uses Akamai's public IP service (http://whatismyip.akamai.com)


##How to use

The AWS-related logic is invoked from caribou.rb
It will be able to automatically set up and deploy an EC2 instance to use as the basis for further deployments.
```
CARIBOU
-------

Usage: C:/Users/pita/dev/caribou/caribou.rb <command> [options]

Command can be one of:
list       - List all AWS regions available with the credentials provided
getsgid    - Get the ID of the default AWS Security Group Caribou will use
deploy_master - Deploy the Caribou Master Node
master_status - Get the status of the currently deployed Caribou Master Node
shutdown   - Shutdown the Caribou Cluster

Specific options:
    -a, --awskeyid ID                The AWS key ID to use
    -r, --region REGION              The AWS region to use
    -k, --keypair-name NAME          The key pair name to use for master node
    -i, -master-instance-type TYPE
    -t, --master-image-id ID
    -s GROUPNAME,                    The AWS EC2 Security Group name to use
        --security-group-name
        --new-key                    When deploying a new EC2 instance, also create a new keypair if none is provided
        --key-file FILE              SSH public key to import
    -f, --cfgfile FILE               Load configuration from FILE
    -v, --verbose                    Show verbose logging
    -h, --help                       Show this message
        --version                    Show version information
```

##Notes
* Currently uses Aws.use_bundled_cert! for an easy way to work on Windows.

*The entirety of this project is covered by the [GNU General Public License, Version 3](http://www.gnu.org/licenses/gpl-3.0.txt)*
