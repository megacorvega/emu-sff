[global]
server min protocol = NT1
workgroup = WORKGROUP
usershare allow guests = yes
map to guest = bad user
allow insecure wide links = yes

[share]
comment = shared folder
path = /share
browseable = yes
writable = yes
create mask = 0777
directory mask = 0777
public = yes
guest ok = yes
force user = root
follow symlinks = yes
wide links = yes
