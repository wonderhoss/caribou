# Caribou - An Exercise in Infrastructure-as-Code

##Requirements
* AWS SDK for Ruby v2
* NetAddr

* Uses Akamai's public IP service (http://whatismyip.akamai.com)


##How to use

The AWS-related logic is invoked from caribou.rb
It will be able to automatically set up and deploy an EC2 instance to use as the basis for further deployments.
```
CARIBOU
-------

Usage: C:/Users/pita/dev/caribou/caribou.rb <command> [options]

Command can be one of: list getsgid

Specific options:
    -k, --awskeyid ID                The AWS key ID to use
    -r, --region REGION              The AWS region to use
    -s GROUPNAME,                    The AWS EC2 Security Group name to use
        --security-group-name
    -f, --cfgfile FILE               Load configuration from FILE
    -v, --verbose                    Show verbose logging
    -h, --help                       Show this message
        --version                    Show version information
```

##Notes
* Currently uses Aws.use_bundled_cert! for an easy way to work on Windows.

*The entirety of this project is covered by the [GNU General Public License, Version 3](http://www.gnu.org/licenses/gpl-3.0.txt)*
