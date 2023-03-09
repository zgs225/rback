rback
===

This is a Bash script to backup local directories to remote cloud storage using rclone. It reads configurations from a JSON file (config.json by default) and generates rclone config files automatically. It creates a backup archive file in tar.gz format and uploads it to the remote cloud storage. It can also remove the older backups according to the retention policy.

## Usage

``` sh
./rback.sh [-c config_file] [-v] [-h]
```

Options:

* `-c config_file`: specify the path of the configuration file. Default is `config.json`.
* `-h`: show help.
* `-v`: verbose mode.

## Dependencies

* rclone: A command line program to sync files and directories to and from cloud storage services.
* jq: A lightweight and flexible command-line JSON processor.

## Configurations

The config.json file has the following format:

``` json
{
  "sync_dir": "~/.rback",
  "providers": [
    {
      "name": "provider1",
      "type": "provider1_type",
      "provider_key1": "value1",
      "provider_key2": "value2"
    },
    {
      "name": "provider2",
      "type": "provider2_type",
      "provider_key1": "value1",
      "provider_key2": "value2"
    }
  ],
  "backups": [
    {
      "local_dir": "~/Documents",
      "exclude": ["*.log", "*.tmp"],
      "include": ["important_file"],
      "provider": "provider1",
      "remote_path": "/path/to/remote/dir",
      "retention": 14,
      "bucket": "my_bucket"
    },
    {
      "local_dir": "~/Pictures",
      "exclude": [],
      "include": [],
      "provider": "provider2",
      "remote_path": "/path/to/remote/dir",
      "retention": 7,
      "bucket": "my_bucket"
    }
  ]
}
```

* `sync_dir`: The local directory to store backup archives. Default is `~/.rback`.
* `providers`: The list of cloud storage providers used by rclone. Each provider is defined by its name and its specific configurations. Refer to [rclone document](https://rclone.org/docs/) to check more details about providers.
* `backups`: The list of backup directories to be backed up. Each backup is defined by its local directory, its exclusion rules, its inclusion rules, its provider, its remote path, its retention policy, and its bucket name.
