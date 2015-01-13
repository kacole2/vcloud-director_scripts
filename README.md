# Ruby scripts that show how to interact with the vCloud API
This will automatically create a new vCloud organisation + VDC, VShield Edge and VCD Network
It will also create the default SNAT rule and Allow all outbound Firewall rule.

## Setup for Windows

* Head to http://rubyinstaller.org/downloads/ and download the 32bit ruby 1.9.3 installer for windows
* Install it, when you get to the screen asking for a destination install folder, tick the "add ruby to path" and "associate rb files" tickboxes

Now open a fresh command prompt to get the new environment variables

* run   -> gem install rest-client
* run   -> gem install nokogiri

That will get you the two required Gems that these scripts lean on

* run the scripts as per the section at the bottom of this file

## Setup for Mac OSX

Plenty of ways to tackle this, i went with:

* Install Xcode command line tools, open a terminal on your mac, then type "git" or "gcc" it will propmt you to download and install the tool-chain
* Head over to homebrew and install that (http://brew.sh)
* Head over to RVM (ruby version manager) and grba that (http://rvm.io)
* Pull down a later version of ruby and create a new gemset with RVM if you want, but not strictly needed

* Open a new terminal and run -> gem install rest-client
* Also run  -> gem install nokogiri

Ok that is pretty much it, clone this repo, change director into it and run the scripts below

## How to run the scripts

1. Edit the config file (_config.yml) enter your username and password and desired organization name
2. Run ruby .\1NewOrg.rb
3. Run ruby .\2NewOrgVDC.rb
4. Run ruby .\3NewOrgVDCNetwork.rb

## NOTE:  you might need to run script 3 a few times if it throws a 400 error, seems that vCloud takes a while to be ready for a vDC network creation after deploying a new edge.


