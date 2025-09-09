# Easy SSM Port Forwarding Setup on Windows

I have put together a PowerShell script that downloads and installs (if necessary):

- AWS CLI v2
- AWS Session Manager Plugin

After which it uses the provided configuration to start an AWS SSM PortForwarding session.

## Run

You run it like this (of course `config.json` can be named as you like)

```powershell
.\windows-port-forward-setup-for-iam-user.ps1 -ConfigPath .\config.json
.....
Starting session with SessionId: random-username-2njkkexivx7hubusxzyyz5lg3y
Port 4444 opened for sessionId random-username-2njkkexivx7hubusxzyyz5lg3y.
Waiting for connections...
```

## Configuration

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

This will set up port forwarding from `localhost:4444` to `i-123456789abcdef:3389`.

# Combining with RDP

Once the shell has output `Waiting for connections` you are now ready to connect.
So open your RDP client and connect to `localhost:{$localPort}`, and provide the usual credentials for that connection.

Voila, secure RDP without a publicly open port.
This can also work with non-AWS machines but setting up AWS SSM Agent on the node and registering it as part of your fleet. Useful for hybrid or multi-cloud environments.

# Side-Note

Of course this just a wrapper for an `aws ssm start-session` call, so you can extract the key components and run independently for yourself:

```bash
aws ssm start-session \
	--region $region \
	--target $instanceId \
	--document-name "AWS-StartPortForwardingSession" \
	--parameters portNumber=$targetPort,localPortNumber=$localPort
```
