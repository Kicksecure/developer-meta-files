
https://whonix.org/wiki/Dev/Build_Documentation
https://phabricator.whonix.org/T577#10979

To get an overview of all switches:
https://github.com/Whonix/Whonix/blob/master/help-steps/parse-cmd#L106

Assign 4 CPUs and as close to 4GB RAM as possible to avoid the build process erroring out with a cryptic error.




To get pinentry working during build preparation:
pinentry-gnome3




To create a key for signify-openbsd as user "user":

sudo apt-get install signify-openbsd
mkdir -p ~/.signify
cd ~/.signify
signify-openbsd -n -G -p keyname.pub -s keyname.sec

Restore folder from backup in VM home dir and rename signify -> .signify




Generating a SSH public key (only needed once initially):

ssh-keygen -t ed25519



Upload single file to SSH server:

ssh hulahoop,whonix-kvm@frs.sourceforge.net "/bin/bash -i"

Verify server fingerprint: SHA256:QAAxYkf0iI/tc9oGa0xSsVOAzJBZstcO8HqGKfjpxcY

Enter sf.net password

scp [$file in /home/user] hulahoop,whonix-kvm@frs.sourceforge.net:/home/frs/project/whonix-kvm/libvirt



Install rsync and SSH to upload:

sudo apt-get install rsync ssh



Run ssh-keygen to re-create .ssh folder then restore Whonix keys from backup.

Set permissions for SSH to work:

chmod -R og-rwx .ssh



In future, source code can be updated as per:

~/Whonix/packages/whonix-developer-meta-files/debug-steps/git-tag-checkout-latest

Output of above script needs to be read and understood for security and
reliability.




