rback
===

A backup script using rclone.

## Dependencies

* jq
* rclone

## Example

``` sh
rback.sh -c config.json
```

## Config

``` json
{
    "sync_dir": "${HOME}/.rback/",
    "providers": [
        {
            "name": "r2",
            "type": "s3",
            // Other options ...
        }
    ],
    "backups": [
        {
            "local_dir": "${HOME}/.ssh/",
            "provider": "r2",
            "bucket": "yuez-private-bucket",
            "remote_path": "ssh/",
            "retention": "5",
            "exclude": [
                "known_hosts",
                "authorized_keys"
            ],
            "include": [
                "known_hosts",
                "authorized_keys"
            ]
        }
    ]
}
```
