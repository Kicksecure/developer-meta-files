## How to install `%%package-name%%` using apt-get ##

1\. Download the APT Signing Key.

```
wget https://www.%%project_clearnet%%/keys/derivative.asc
```

Users can [check the Signing Key](https://www.%%project_clearnet%%/wiki/Signing_Key) for better security.

2\. Add the APT Signing Key.

```
sudo cp ~/derivative.asc /usr/share/keyrings/derivative.asc
```

3\. Add the derivative repository.

```
echo "deb [signed-by=/usr/share/keyrings/derivative.asc] https://deb.%%project_clearnet%% bookworm main contrib non-free" | sudo tee /etc/apt/sources.list.d/derivative.list
```

4\. Update your package lists.

```
sudo apt-get update
```

5\. Install `%%package-name%%`.

```
sudo apt-get install %%package-name%%
```

## How to Build deb Package from Source Code ##

Can be build using standard Debian package build tools such as:

```
dpkg-buildpackage -b
```

See instructions.

NOTE: Replace `generic-package` with the actual name of this package `%%package-name%%`.

* **A)** [easy](https://www.%%project_clearnet%%/wiki/Dev/Build_Documentation/generic-package/easy), _OR_
* **B)** [including verifying software signatures](https://www.%%project_clearnet%%/wiki/Dev/Build_Documentation/generic-package)

## Contact ##

* [Free Forum Support](https://forums.%%project_clearnet%%)
* [Premium Support](https://www.%%project_clearnet%%/wiki/Premium_Support)

## Donate ##

`%%package-name%%` requires [donations](https://www.%%project_clearnet%%/wiki/Donate) to stay alive!
