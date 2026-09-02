<!--
SPDX-FileCopyrightText: 2026 Ryan Lahfa <ryan.lahfa@numerique.gouv.fr>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Deployment Options

Most of these methods are architectural ideas, the default implementation is the first one.

Bureautix implements most of the next ones.

## 1. USB Installer for Each System

This deployment method involves creating a separate USB installer for each individual system. 
Each USB drive contains the necessary installation files tailored to the specific system configuration. 

When the user boots from this USB, the installer will directly install a specific NixOS closure after `autoinstall-terminal` is invoked.

This method is practical when you have few systems and no infrastructure, it's the default method.

## 2. Generic "Mass" USB Installer

The "Mass" USB installer is designed to simplify the deployment of multiple systems. It contains a list of pre-configured systems, each indexed by its serial number. When you boot a machine using this USB installer, the system checks its serial number and automatically selects the appropriate system configuration to deploy. This way, you can have a single USB installer for multiple systems, each one automatically configured according to its serial number.

This method is practical when you mass install multiple systems based on serial *in serial*. It requires a large USB stick if all the multiple systems have high amount of unique customization leading to large closures.

This method is implemented as [an example in Bureautix](https://github.com/cloud-gouv/bureautix-example/blob/main/default.nix#L188-L212).

## 3. Generic Online USB Installer

The Generic Online USB installer works similarly to the Mass USB installer, but with a key difference: it connects to an external website during the installation process. Upon booting from the USB, the system sends its serial number to the website, which redirects to a NixOS closure tailored for that specific serial number.

The target website must act as a Nix cache, once the redirection is performed, Nix will copy the toplevel closure in memory.

This method is practical when configurations are all built from CI and pushed to a cache that can be reached in the installer environment. The USB stick can be burned once and stays relatively up-to-date as long as disk layouts or special boot features do not change.

This method can be implemented using [an example in Bureautix](https://github.com/cloud-gouv/bureautix-example/blob/main/default.nix#L188-L212) and adding more system closures.

## 4. Netboot Installation

The Netboot installation method is a lightweight solution where the installer is sent via PXE (Preboot Execution Environment) instead of a physical USB drive. When a system is booted, it retrieves the installer over the network (typically via HTTP or TFTP) and downloads the rest of the necessary installation files. This enables you to perform installations without needing physical media on hand.

This method is practical for physical device testing development cycles, mass deployment on-site and even online deployments if your OEM supports HTTP boot and you have a mechanism to authenticate the originating system.

This method is implemented as [an example in Bureautix](https://github.com/cloud-gouv/bureautix-example/tree/main/netboot).
