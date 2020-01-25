Function Add-ContentLibraryItem {
    <#
    .NOTES :
    --------------------------------------------------------
    Creaded by: Eric B Lee
    Website : https://github.cerner.com/CTS/VirtOps
    Some code referenced from: Stuart Yerdon
    Code referenced Website : https://notesofascripter.com/2018/12/18/how-add-vm-content-library-powercli/
    --------------------------------------------------------
    .DESCRIPTION
    This function uploads a VM to the Content library.
    .PARAMETER LibraryName
    Name of the libray to which item needs to be uploaded.
    .PARAMETER LibItemName
    Name of the template after imported to library.    
    .PARAMETER ItemURL
    URL to pull OVA file from
    .PARAMETER Description
    Description of the imported item.
    .EXAMPLE
    Add-ContentLibraryItem -LibraryName 'LibraryName' -LibItemName '2016-Core-Template' -ItemURL "https://webaddress.com/2016-Core-Template.ova" -Description 'Uploaded via API calls'
    #>
     
    param(
    [Parameter(Mandatory=$true)][string]$LibraryName,
    [Parameter(Mandatory=$true)][string]$LibItemName,
    [Parameter(Mandatory=$true)][string]$ItemURL,
    [Parameter(Mandatory=$true)][string]$Description
    )
     
    # Make sure vCenter server is 6.7. HTTP(s) import not supported on 6.5 or older
    If($global:DefaultVIServers.version -lt "6.7.0"){
        Write-Host -ForegroundColor red "$(get-date -format g): $($vCenter) server version is not supported by this function. "
        #Exit
    }


    # Make sure Content Library exists
    $library_ID = (Get-ContentLibrary -Name $LibraryName).ID 
    IF(!$library_ID){
        Write-Host -ForegroundColor red "$(get-date -format g): $($LibraryName) does not exist. Exiting process."
        Exit
    } Else {
        Write-Host -ForegroundColor Green "$(get-date -format g): $($LibraryName) Is there. Let's GOOOO!!!!!"
    }
    
    
    # Check to see if item already exists 
    $ContentLibraryItemService = Get-CisService com.vmware.content.library.item
    $libraryItems = $ContentLibraryItemService.list($library_ID)
    foreach($libraryItem in $libraryItems) {
        $item = $ContentLibraryItemService.get($libraryItem)
        if($item.name -eq $LibItemName){
            $CLitem_ID = $libraryItem
            break
            }
    }
   
    # Get URL Cert Thumbprint - Import will fail if Cert chain not fully validated or root Certs not imported to vCenter
    $CLitemWebSiteRequest = [Net.WebRequest]::Create($ItemURL)
    Try { $CLitemWebSiteRequest.GetResponse() } catch {}
    $CLitemWebSiteCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 ($CLitemWebSiteRequest.ServicePoint.Certificate)
    # Converting to proper format for vCenter API
    $CLitemWebSiteCertThumbprint = ($CLitemWebSiteCert.Thumbprint -replace '(..)','$1:') -replace ".$"

    #   Unique ID for API access
    $UniqueChangeId = [guid]::NewGuid().tostring()


    #####   Main Process
  
    # Create Item if it doesn't exist.
    If(!$CLitem_ID){
        ##  Create CL Item
        $ItemCreateSpec = $ContentLibraryItemService.Help.create.create_spec.Create()
        $ItemCreateSpec.library_id = $library_ID
        $ItemCreateSpec.name = $LibItemName
        #$ItemCreateSpec.type = "OVF"
        $CLitem_ID = $ContentLibraryItemService.create($UniqueChangeId,$ItemCreateSpec)
    }
    
    # Get current content version
    $CLItemCurrentVersion = ($ContentLibraryItemService.get($CLitem_ID)).content_version


    # Create Update Session
    $ContentLibraryUpdateSessionService = Get-CisService com.vmware.content.library.item.update_session
    $ItemUpdateSessionInfo = $ContentLibraryUpdateSessionService.Help.create.create_spec.Create()
    $ItemUpdateSessionInfo.library_item_id = $CLitem_ID
    $ItemUpdateSessionID = $ContentLibraryUpdateSessionService.create($UniqueChangeId,$ItemUpdateSessionInfo)
    start-sleep -s 2

    # Upload Image Endpoint
    $ContentLibraryUpdateSessionFileService = Get-CisService com.vmware.content.library.item.updatesession.file
    $ItemUpdateSessionEndpointType = $ContentLibraryUpdateSessionFileService.Help.add.file_spec.Create()
    $ItemUpdateSessionEndpointType.name = $LibItemName
    $ItemUpdateSessionEndpointType.source_endpoint.uri = $ItemURL
    $ItemUpdateSessionEndpointType.source_endpoint.ssl_certificate_thumbprint = $CLitemWebSiteCertThumbprint
    $ItemUpdateSessionEndpointType.source_type = "PULL"
    $ItemUpdateEndpoint = $ContentLibraryUpdateSessionFileService.add($ItemUpdateSessionID,$ItemUpdateSessionEndpointType)


    # Check status until file is fully uploaded
    $ContentLibraryUploadStatus = $ContentLibraryUpdateSessionFileService.list($ItemUpdateSessionID)
    DO{
    start-sleep -s 10
    $ContentLibraryUploadStatus = $ContentLibraryUpdateSessionFileService.list($ItemUpdateSessionID)
    Write-Host -ForegroundColor Green      Bytes left to transfer: ($ContentLibraryUploadStatus[0].size - $ContentLibraryUploadStatus[0].bytes_transferred)
    } While (($ContentLibraryUploadStatus[0].size - $ContentLibraryUploadStatus[0].bytes_transferred) -gt 0)
    Write-Host -ForegroundColor Yellow "$(get-date -format g):      Transfer Completed"


    # If file uploaded - Mark as "Validated" and "Completed" then updated DESCRIPTION
    IF(($ContentLibraryUpdateSessionFileService.list($ItemUpdateSessionID))[0].status = "READY"){
        $ContentLibraryUpdateSessionFileService.validate($ItemUpdateSessionID)
        
        # Complete session so CL item is updated and task completed. Wait 5 seconds for the process to finish on vCenter.
        $ContentLibraryUpdateSessionService.complete($ItemUpdateSessionID)
        start-sleep -s 5

        # Validate file applied to image item.
        If(($ContentLibraryItemService.get($CLitem_ID)).content_version -gt $CLItemCurrentVersion){
            # Update Description:
            $ItemUpdateSpec = $ContentLibraryItemService.Help.update.update_spec.Create()
            $ItemUpdateSpec.description = $Description
            $ItemUpdateSpec.library_id = $CLitem_ID
            $CLItemUpdate = $ContentLibraryItemService.update($CLitem_ID,$ItemUpdateSpec)
        }
    } else {
        # Cancel Update Session
        $ContentLibraryUpdateSessionService.cancel($ItemUpdateSessionID)
    }

    # Finalize process by deleteding update session.
    $ContentLibraryUpdateSessionService.delete($ItemUpdateSessionID)
        
}
