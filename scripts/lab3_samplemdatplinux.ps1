Configuration MdatpHealthCheck {
    Import-DscResource -ModuleName 'nxtools'
 
    Node localhost
    {
        #mdatp Service
        nxService mdatprunning {
            Name    = 'mdatp.service'
            State   = 'running'
            Enabled = $true
            Controller = 'systemd'
        }
    }
}
 
$OutputPath = "./"
New-Item $OutputPath -Force -ItemType Directory
 
# Gerar o arquivo MOF
MdatpHealthCheck -OutputPath $OutputPath
 
# Gerar o arquivo de configuração ZIP
New-GuestConfigurationPackage -Name "AzureArcJumpStart_Linux" -Configuration "$OutputPath/localhost.mof" -Type AuditandSet -Path $OutputPath -Force
 
# Aplicar o arquivo de configuração ZIP
Start-GuestConfigurationPackageRemediation -Path "$OutputPath/AzureArcJumpStart_Linux.zip"
 
#https://azurearcjumpstart.io/azure_arc_jumpstart/azure_arc_servers/day2/arc_automanage/arc_automanage_machine_configuration_custom_linux
#https://learn.microsoft.com/en-us/powershell/dsc/reference/resources/linux/lnxserviceresource?view=dsc-1.1#example