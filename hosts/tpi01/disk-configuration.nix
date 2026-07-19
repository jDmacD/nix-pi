# Example to create a bios compatible gpt partition
{
  disko.devices = {
    disk.external = {
      type = "disk";
      device = "/dev/disk/by-id/ata-Samsung_SSD_870_QVO_4TB_S5STNF0TA02598T";
      content = {
        type = "gpt";
        partitions = {
          nix = {
            size = "32G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix";
              mountOptions = [
                "noatime" # Reduce writes--we don't care about access times
              ];
            };
          };
          var = {
            size = "256G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var";
            };
          };
          store = {
            size = "100%";
          };
        };
      };
    };
  };
}
