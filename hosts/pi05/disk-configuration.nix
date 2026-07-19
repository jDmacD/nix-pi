# Example to create a bios compatible gpt partition
{
  disko.devices = {
    disk.external = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S5GXNX1W310723V";
      content = {
        type = "gpt";
        partitions = {
          var = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var";
            };
          };
        };
      };
    };
  };
}
