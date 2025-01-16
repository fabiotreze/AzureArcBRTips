# Gerenciamento de Conformidade

- [Software Installation Using Machine Configuration and Azure Policy](https://techcommunity.microsoft.com/blog/coreinfrastructureandsecurityblog/software-installation-using-machine-configuration-and-azure-policy/3695636)
- [Azure Arc JumpStart: Machine Configuration Custom Windows](https://azurearcjumpstart.io/azure_arc_jumpstart/azure_arc_servers/day2/arc_automanage/arc_automanage_machine_configuration_custom_windows)
- [Visão Geral do Machine Configuration no Azure](https://learn.microsoft.com/pt-br/azure/governance/machine-configuration/overview)

**Informações importantes sobre o agent**
[Correção](https://learn.microsoft.com/pt-br/azure/governance/machine-configuration/whats-new/agent)

# Como criar um pacote personalizado
[Como configurar um ambiente de criação de configuração de máquina](https://learn.microsoft.com/pt-br/azure/governance/machine-configuration/how-to/develop-custom-package/1-set-up-authoring-environment)

# Exemplos de utilização do DSC
O repositório abaixo pode ser utilizado como referência para a criação de outros recursos, permitindo a execução de uma variedade infinita de ações com o Guest Configuration e o Azure Arc.
[Github PSDscResources] (https://github.com/PowerShell/PSDscResources/blob/dev/Examples/Sample_MsiPackage_InstallPackageFromHttp.ps1)

### **7-zip**


New-GuestConfigurationPackage `
-Name 'Install7zip_MsiPackageFromHttp' `
-Configuration ".\Install7zip_MsiPackageFromHttp/localhost.mof" `
-Type AuditAndSet `
-Path $OutputPath `
-Force

Start-GuestConfigurationPackageRemediation -Path .\Install7zip_MsiPackageFromHttp.zip