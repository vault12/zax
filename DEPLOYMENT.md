## 1. Start a new droplet with the pre-installed Ruby

* Navigate to the Digital Ocean dashboard and choose the appropriate project from the left menu.
* Click on _Create > Droplets_ to initiate the setup process.

![Screenshot 2024-02-16 at 11 22 56](https://github.com/vault12/zax/assets/1370944/b1dfd86f-63a5-49bb-939d-a2148bbe4a64)

* Under _Choose an Image_, select _Marketplace_ and then opt for the _Ruby On Rails_ image. Ensure it's the appropriate version (e.g., Version 7.0.4.2, OS Ubuntu 22.04).

![Screenshot 2024-02-16 at 11 24 53](https://github.com/vault12/zax/assets/1370944/5009c912-e256-4c48-8590-14572d98facf)

* For authentication, choose the _SSH Key_ option and select your preferred SSH key.
* Click _Create Droplet_ and patiently wait for the droplet to be provisioned.
* You can find more details about the package on the [Ruby on Rails Droplet](https://marketplace.digitalocean.com/apps/ruby-on-rails) page.

## 2. SSH into the Droplet

Once the droplet is ready, access it via SSH using the following command:

```bash
ssh root@your_droplet_ip
```

Replace `your_droplet_ip` with the actual IP address of your newly created droplet.

## 3. Install Redis

Install Redis on the server by following the Digital Ocean guide [How To Install and Secure Redis on Ubuntu 20.04](https://www.digitalocean.com/community/tutorials/how-to-install-and-secure-redis-on-ubuntu-20-04). Here are the summarized steps:

* **Install Redis package**. Run `apt install redis-server`.
* **Update Redis configuration**. Edit `/etc/redis/redis.conf` and set the `supervised` directive to `systemd`.
* **Restart Redis service**. Run `systemctl restart redis.service` to apply the changes.

## 4. Install and configure Zax

* In the SSH console, sign in as the predefined **rails** user:

```bash
su - rails
```

* Clone [Zax repository](https://github.com/vault12/zax), navigate into the directory and run the script to install dependencies:

```bash
git clone https://github.com/vault12/zax.git
cd zax
./install_dependencies.sh
```

* Whitelist your hostname for production use

By default, Rails 6 applications reject all requests that are not made to the configured host. So you need to uncomment and modify line 11 in the [production configuration file](https://github.com/vault12/zax/blob/main/config/environments/production.rb#L11) `config/environments/production.rb`, uncomment the following line and insert your own URL to allow access to the app from your host:

```ruby
config.hosts << "zax.example.com" # use your host name
```

* Disable Zax Dashboard to serve as frontend (optional)

If you want to disable access to the [Zax Dashboard](https://github.com/vault12/zax-dashboard) which provides a convenient UI, set the `public_file_server` variable on line 64 in the [production configuration file](https://github.com/vault12/zax/blob/main/config/environments/production.rb#L64) (`config/environments/production.rb`) to `false`. This action will prevent the Ruby server from serving files from the `public/` directory.

```ruby
config.public_file_server.enabled = false
```

* Exit from the **rails** user session by entering `exit`.

## 4. Modify Rails service to serve Zax

* Open `/etc/systemd/system/rails.service` and update the `WorkingDirectory` and `ExecStart` directives as follows:

```bash
WorkingDirectory=/home/rails/zax/
ExecStart=/bin/bash -lc 'rails s --binding=localhost --environment production'
```

Save the changes and exit the editor.

## 5. Add a DNS record for your domain with your registrar

To configure DNS for your domain, log in to your domain registrar's website and access the DNS management section. Add an A record by specifying your domain name and your droplet's IP address. Save the changes and wait for DNS propagation, which may take some time.

## 6. Configure Nginx and secure it with Let's Encrypt

* **Edit the Nginx configuration file**. In `/etc/nginx/sites-available/rails`), replace `server_name _;` with the correct host name (e.g. `server_name zax.example.com;`).

* **Secure Nginx with Let's Encrypt**. Follow the instructions in the Digital Ocean tutorial [How To Secure Nginx with Let's Encrypt on Ubuntu 20.04](https://www.digitalocean.com/community/tutorials/how-to-secure-nginx-with-let-s-encrypt-on-ubuntu-20-04) to obtain and install SSL/TLS certificates for your domain. Here are the summarized steps:

1. Allow `Nginx Full` through the firewall and delete the rule for `Nginx HTTP`:

```bash
ufw allow 'Nginx Full'
ufw delete allow 'Nginx HTTP'
```

2. Obtain SSL certificate using Certbot with Nginx plugin:

```bash
certbot --nginx -d zax.example.com
```

3. Reload the systemd daemon and restart the Rails service to apply the changes:

```bash
systemctl daemon-reload
systemctl restart rails.service
```

## 7. Verify the installation

Open https://zax.example.com in your browser to ensure Zax Dashboard is served over HTTPS.
