# Gerenciamento de Conformidade

## Referências Técnicos
Importante se atentar aos requerimentos técnicos de módulos para a máquina que será utilizada para criar o pacote personalizado e uso do Azure Policy.

- [Software Installation Using Machine Configuration and Azure Policy](https://techcommunity.microsoft.com/blog/coreinfrastructureandsecurityblog/software-installation-using-machine-configuration-and-azure-policy/3695636)
- [Azure Arc JumpStart: Machine Configuration Custom Windows](https://azurearcjumpstart.io/azure_arc_jumpstart/azure_arc_servers/day2/arc_automanage/arc_automanage_machine_configuration_custom_windows) - **Importante garantir que os módulos estejam instalados na máquina a ser utilizada como referência para criação de pacote personalizado**
- [Visão Geral do Machine Configuration no Azure](https://learn.microsoft.com/pt-br/azure/governance/machine-configuration/overview)

---

### Informações importantes sobre o Agent
[Correção](https://learn.microsoft.com/pt-br/azure/governance/machine-configuration/whats-new/agent)

---

## Como Criar um Pacote Personalizado
[Como configurar um ambiente de criação de configuração de máquina](https://learn.microsoft.com/pt-br/azure/governance/machine-configuration/how-to/develop-custom-package/1-set-up-authoring-environment)

---

## Exemplos de Utilização do DSC
O repositório abaixo pode ser utilizado como referência para a criação de novos recursos, permitindo uma ampla variedade de ações com o **Guest Configuration** e o Azure Arc. Ele contém diversos exemplos de DSC que servem como base e inspiração, simplificando o processo e evitando a necessidade de começar do zero.

- [Github PSDscResources](https://github.com/PowerShell/PSDscResources/tree/dev)
- [Azure Policy built-in packages for guest configuration](https://learn.microsoft.com/en-us/azure/governance/policy/samples/built-in-packages)

---

### **Exemplo: 7-zip**
Com base no documento oficial da Microsoft **Como criar um pacote personalizado**, utilizaremos o exemplo [sample7zip.ps1](https://raw.githubusercontent.com/fabiotreze/AzureArcDemo/refs/heads/main/Lab3/sample7zip.ps1). O script criará o arquivo **localhost.mof**, processado pelo comando abaixo:

```powershell
New-GuestConfigurationPackage `
-Name 'Install7zip_MsiPackageFromHttp' `
-Configuration ".\Install7zip_MsiPackageFromHttp/localhost.mof" `
-Type AuditAndSet `
-Path .\ `
-Force
```

O comando gerará o pacote necessário para aplicar e auditar a configuração desejada. Para realizar testes, podemos copiar o arquivo **Install7zip_MsiPackageFromHttp.zip** para um servidor e validá-lo utilizando o seguinte comando:

```powershell
Start-GuestConfigurationPackageRemediation -Path .\Install7zip_MsiPackageFromHttp.zip
```

---

# Como próximo passo, podemos avançar na utilização deste arquivo para a criação de uma definição de política no Azure.
[Como criar definições de políticas de configuração de computador personalizadas](https://learn.microsoft.com/pt-br/azure/governance/machine-configuration/how-to/create-policy-definition)

Podemos seguir as orientações do artigo, de armazenar em uma **Storage Account**, com isso pegar o **URI** para utilização no comando mais abaixo:

```powershell
$contentUri = "https://arcboxmachineconfigyqvkt.blob.core.windows.net/machineconfiguration/Install7zip_MsiPackageFromHttp.zip" #O acesso pode não estar disponível aqui; este é apenas um exemplo ilustrativo. :-)**
$contentUri

$PolicyConfig      = @{
  PolicyId      = '704dccbb-132a-4eb8-b6a4-409608b5b2ee' #Utilize new-guid no powershell para gerar um novo GUID
  ContentUri    = $contentUri
  DisplayName   = '(ArcBox - Custom) My policy Apply_and_Autocorrect - Install7zip_MsiPackageFromHttp'
  Description   = '(ArcBox - Custom) My policy Apply_and_Autocorrect - Install7zip_MsiPackageFromHttp'
  Path          = './policies/auditIfNotExists.json'
  Platform      = 'Windows'
  PolicyVersion = '1.0.0'
  Mode          = 'ApplyAndAutoCorrect'
}

New-GuestConfigurationPolicy @PolicyConfig -verbose
```
Na sua pasta de execução será criada a estrutura de pasta **\policies\auditIfNotExists.json** com pelo menos 2 arquivos

```plaintext
.\Install7zip_MsiPackageFromHttp_AuditIfNotExists.json
.\Install7zip_MsiPackageFromHttp_DeployIfNotExists.json
```

Utilize o comando abaixo Powershell para a criação dos Azure Policy
```powershell
New-AzPolicyDefinition -Name '(ArcBox-Custom)-Install7zipMsiPackageFromHttpAuditIfNotExists' -Policy '.\Install7zip_MsiPackageFromHttp_AuditIfNotExists.json' -verbose
New-AzPolicyDefinition -Name '(ArcBox-Custom)-Install7zipMsiPackageFromHttpDeployIfNotExists' -Policy '.\Install7zip_MsiPackageFromHttp_DeployIfNotExists.json' -verbose
```
Após espero que esteja disponível a Definition no Azure Policy para avaliação e assignments.

---

# DICA EXTRA

Nos passos mencionados anteriormente, foram criados arquivos JSON que serão utilizados no **Azure Policy**, especificamente para a criação das **Definitions**.

Entre essas definições, destaca-se a **DeployIfNotExists**, cuja estrutura segue um formato semelhante ao exemplo apresentado. Temos 2 campos importantes **contentUri** e **contentHash**.

```json
"guestConfiguration": {
                "name": "Install7zip_MsiPackageFromHttp",
                "version": "1.0.0",
                "contentType": "Custom",
                "contentUri": "https://arcboxmachineconfigyqvkt.blob.core.windows.net/machineconfiguration/Install7zip_MsiPackageFromHttp.zip",
                "contentHash": "XE5268417B0246DB936CB5C249C8CADF18590F214D399825950A39E381A30491DD"
            }
```

Podemos fazer o uso para a criação do **Guest Assignments** e utilizar com a funcionalidade do **Machine Configuration** juntamente do Azure Arc.

[Atribuir uma configuração](https://learn.microsoft.com/pt-br/azure/governance/machine-configuration/how-to/assign-configuration/overview)

Talvez surja a dúvida: quando devo utilizar o **Guest Configuration** e quando utilizar o **Azure Policy**?

Lembre-se de que as informações apresentadas abaixo são apenas exemplos e não se limitam ao que está mostrado na tabela, podendo ser aplicadas de forma mais ampla conforme o cenário.

| **Aspecto**               | **Azure Policy**                              | **Guest Configuration (Machine Configuration)** |
|----------------------------|-----------------------------------------------|-------------------------------------------------|
| **Escopo**                | Infraestrutura e recursos                    | Sistema Operacional (Guest OS)                 |
| **Habilitação**           | Regras para recursos gerenciados             | Extensão de VM ou Azure Arc                    |
| **Granularidade**         | Macro (recursos, regiões, tags)              | Micro (SO, serviços, arquivos)                 |
| **Exemplos de Uso**       | Restrições de local, SKUs, tags               | Configurações de SSH, serviços, arquivos       |
| **Compatibilidade com Azure Arc** | Sim                                   | Sim                                             |
| **Correção Automática**   | Limitada (aplica-se à infraestrutura)        | Sim (aplica-se à configuração no SO)           |