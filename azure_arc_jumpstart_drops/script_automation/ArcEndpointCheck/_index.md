---
type: docs
title: "Azure Arc Connectivity Check"
linkTitle: "Azure Arc Connectivity Check"
weight: 1
description: >
---

## Overview  

This script was created to help identify connectivity issues with the Azure Arc Machine Agent and its endpoints. It allows you to test the necessary URLs to ensure the agent can communicate correctly with the various requirements for its operation.

This script checks the connectivity and status of Azure endpoints, validates Azure Arc functionality, and performs DNS resolution, network connectivity, and HTTP request tests, logging the results for review.

## Getting Started

To use this script, follow these essential steps:

1. **Define the Region**  
   Set the region for your Azure Arc deployment. For example:  
   `$region = "brazilsouth"`

2. **Define the Log File Path**  
   Specify the location where the log file will be saved. For example:  
   `$logFilePath = "C:\temp\Arclogfile.txt"`

3. **Choose Public or Private Deployment**  
   Determine whether your Azure Arc instance will be public or private.  
   If you're using a public deployment, make sure to remove the `--enable-pls-check` parameter from the script.

## Using the Script

Execute the script from the server where the Azure Arc Agent will be installed. It's important to consider the environment, taking into account factors such as firewall, proxy, region, and whether the connection is public or private. Make necessary adjustments to the script based on these aspects. In one part of the script, it tests with `AzcmAgent.exe`; in this case, ensure that the Azure Arc Agent is already installed.

### Prerequisites

- PowerShell
- Network connectivity

## Contributions

Contributions are welcome! Feel free to open an _issue_ or submit a _pull request_ to improve this repository.