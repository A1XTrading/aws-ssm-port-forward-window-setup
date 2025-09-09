# Easy SSM Port Forwarding Setup on Windows

I have put together a PowerShell script that downloads and installs (if necessary):

- AWS CLI v2
- AWS Session Manager Plugin

After which it uses the provided configuration to start an AWS SSM PortForwarding session.

## Run

Because we are running installers we require `Run As Administrator`. It will trigger all installers to appears as pop-up installer for full transparency.

```powershell
.\windows-port-forward-setup-for-iam-user.ps1 -ConfigPath .\config.json
.....
Starting session with SessionId: random-username-2njkkexivx7hubusxzyyz5lg3y
Port 4444 opened for sessionId random-username-2njkkexivx7hubusxzyyz5lg3y.
Waiting for connections...
```

_of course `config.json` can be named as you like_

## Configuration

These are the required contents of your JSON configuration file:

```json
{
  "accessKeyId": "XXXXXXX",
  "secretAccessKey": "XXXXXX",
  "region": "us-east-1",
  "localPort": 4444,
  "instanceId": "i-123456789abcdef",
  "targetPort": 3389
}
```

This config would set up a port forwarding session from `localhost:4444` to `i-123456789abcdef:3389`.

# Combining with RDP

Once the shell has output `Waiting for connections` you are now ready to connect.
So open your RDP client and connect to `localhost:{$localPort}`, and provide the usual credentials for that connection.

Voila, secure RDP without a publicly open port.
This can also work with non-AWS machines but setting up AWS SSM Agent on the node and registering it as part of your fleet. Useful for hybrid or multi-cloud environments.

## Windows: Multiple Connections with Different Credentials

You may find (like us) that you want to run multiple RDP connections through this system. Whilst MacOS doesn't have an issue with storing credentials per `host:port` combination, We have found native **Windows** support for swapping between user credentials for different `locahost` ports to be non-existent.

We found a workaround, which is the edit the `C:\Windows\System32\drivers\etc\hosts` file and give custom names for each of your connection, for example say you have 3 machines for each you want separate credentials:

- Machine1 is using `localhost:4444`
- Machine2 is using `localhost:4445`
- Machine3 is using `localhost:4446`

Therefore adding this to to bottom of the `hosts` file:

```
127.0.0.1     machine1.local
127.0.0.1     machine2.local
127.0.0.1     machine3.local
```

And then using those names in the RDP client allows each to have their own credentials saved, e.g.:

```bash
# This can default to a different set of credentials
mstsc /v:machine1.local:4444
# To this one
mstsc /v:machine2.local:4445
```

# Side-Note

Of course this just a wrapper for an `aws ssm start-session` call, so you can extract the key components and run independently for yourself:

```bash
aws ssm start-session \
	--region $region \
	--target $instanceId \
	--document-name "AWS-StartPortForwardingSession" \
	--parameters portNumber=$targetPort,localPortNumber=$localPort
```
