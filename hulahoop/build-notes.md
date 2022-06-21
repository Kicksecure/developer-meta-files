= 16.0.5.3 =

upload command:

```
~/derivative-maker/packages/kicksecure/developer-meta-files/release/upload_images --build --target qcow2 --flavor kicksecure-xfce
```

```
~/derivative-maker/packages/kicksecure/developer-meta-files/release/upload_images --build --target qcow2 --flavor whonix-workstation-xfce
```

Note: No need to repeat for `--whonix-gateway-xfce` because of unified libvirt images.

= 16.0.5.4 and above =

upload command:

```
dm-upload-images --build --target qcow2 --flavor kicksecure-xfce
```

```
dm-upload-images --build --target qcow2 --flavor whonix-workstation-xfce
```

Note: No need to repeat for `--whonix-gateway-xfce` because of unified libvirt images.
