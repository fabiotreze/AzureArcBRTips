Configuration Install7zip_MsiPackageFromHttp
{
    Import-DscResource -ModuleName 'PSDscResources'

    Node localhost
    {
        MsiPackage MsiPackage1
        {
            ProductId = '{23170F69-40C1-2702-2409-000001000000}'
            Path = 'https://7-zip.org/a/7z2409-x64.msi'
            Ensure = 'Present'
        }
    }
}

Install7zip_MsiPackageFromHttp