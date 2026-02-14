# misc #

* https://whonix.org/wiki/Dev/Build_Documentation
* https://phabricator.whonix.org/T577#10979

To get an overview of all switches:

https://github.com/derivative-maker/derivative-maker/blob/master/help-steps/parse-cmd#L106

Assign 4 CPUs and as close to 4GB RAM as possible to avoid the build process erroring out with a cryptic error.

# gpg timeout #

* https://github.com/jessfraz/dotfiles/blob/master/.gnupg/gpg-agent.conf
* https://www.gnupg.org/documentation/manuals/gnupg/Agent-Options.html

Increase GPG timeout limit to avoid signing failure. Password rentry required after compression. Press 'c' to ignore and continue the signing process during the prepare release step:

```
echo -e "pinentry-program /usr/bin/pinentry-gnome3\nno-grab\ndefault-cache-ttl 18000\nmax-cache-ttl 86400\nignore-cache-for-signing\npinentry-timeout 86400" | tee -- ~/.gnupg/gpg-agent.conf
```

# gpg pinentry #

To get `pinentry` working during build preparation:

```
pinentry-gnome3
```

# signify #

To create a key for signify-openbsd as account "user":

```
sudo apt-get install signify-openbsd
mkdir -p ~/.signify
cd ~/.signify
signify-openbsd -n -G -p keyname.pub -s keyname.sec
```

Restore folder from backup in VM home dir and rename `signify` -> `.signify`

# ssh key generation #

Generating a SSH public key (only needed once initially!):

```
ssh-keygen -t ed25519
```

Creating SSH server pub key via cli (can be also done manually by saving the contents in a `.pub` file). May need to delete `~/.ssh/known_hosts` if previous attempts failed. This step is not necessary because the keys are saved in the backed up `.ssh`:

```
ssh-keygen -lf ssh_host_ed25519_key.pub
```

```
256 SHA256:tsvKWEuUwbP0vx+vrePlMqbC4qUXn5fscrm/lZLhVrE
root@Debian-98-stretch-64-minimal (ED25519)
```

# Install rsync and SSH to upload #

```
sudo apt-get install rsync ssh
```

Run ssh-keygen to re-create `.ssh` folder then restore Whonix keys from backup.

Set permissions for SSH to work:

```
chmod -R og-rwx .ssh
```

# source code updates #

If package `developer-meta-packages` is already installed:

```
dm-git-tag-checkout-latest
```

Otherwise:

```
"$HOME/derivative-maker/packages/kicksecure/developer-meta-files/usr/bin/dm-git-tag-checkout-latest"
```

Output of above script needs to be read and understood for security and reliability.
