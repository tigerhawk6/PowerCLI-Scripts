Function Add-ContentLibraryItem {
    <#
    .NOTES :
    --------------------------------------------------------
    Created by : Stuart Yerdon
    Website : https://notesofascripter.com/2018/12/18/how-add-vm-content-library-powercli/
    Modified by: Eric B Lee
    Website : https://github.cerner.com/CTS/VirtOps
    --------------------------------------------------------
    .DESCRIPTION
    This function uploads a VM to the Content library.
    .PARAMETER LibraryName
    Name of the libray to which item needs to be uploaded.
    .PARAMETER LibItemName
    Name of the template after imported to library.    
    .PARAMETER ItemURL
    Name of the template after imported to library.
    .PARAMETER Description
    Description of the imported item.
    .EXAMPLE
    Add-TemplateToLibrary -LibraryName 'LibraryName' -VMname '2016 STD Template v1.0 VM' -LibItemName '2016 STD Template' -Description 'Uploaded via API calls'
    #>
     
    param(
    [Parameter(Mandatory=$true)][string]$LibraryName,
    [Parameter(Mandatory=$true)][string]$LibItemName,
    [Parameter(Mandatory=$true)][string]$ItemURL,
    [Parameter(Mandatory=$true)][string]$Description
    )
     
    # Make sure Library exists
    $library_ID = (Get-ContentLibrary -Name $LibraryName).ID 
    IF(!$library_ID){
        Write-Host -ForegroundColor red "$(get-date -format g): $($LibraryName) does not exist. Exiting process."
        Exit
    } Else {
        Write-Host -ForegroundColor Green "$(get-date -format g): $($LibraryName) Is there. Let's GOOOO!!!!!"
    }
    
    
    # Check to see if item already exists 
    $existingClItem = Get-ContentLibraryItem -ContentLibrary $LibraryName -Name $LibItemName



    ###########   Update from here


    # Add/update item
    $ContentLibraryOvfService = Get-CisService com.vmware.vcenter.ovf.library_item
    $UniqueChangeId = [guid]::NewGuid().tostring()
    $createOvfTarget = $ContentLibraryOvfService.Help.create.target.Create()
    $createOvfTarget.library_id = $library_ID

    if(!$item_ID){
        write-host -ForegroundColor yellow $LibItemName "doesn't exist. Creating it"
    } else {
        write-host -ForegroundColor yellow $LibItemName "exist. Will update library item."
        write-host
        # Passes ID of existing library item so it updates instead of creating new item with same name
        $createOvfTarget.library_item_id = $item_ID
        
        write-host -ForegroundColor yellow "Updating Library Item -- " $LibItemName
    }

    $createOvfSource = $ContentLibraryOvfService.Help.create.source.Create()
    $createOvfSource.type = ((Get-VM $VMname).ExtensionData.MoRef).Type
    $createOvfSource.id = ((Get-VM $VMname).ExtensionData.MoRef).Value
        
    $createOvfCreateSpec = $ContentLibraryOvfService.help.create.create_spec.Create()
    $createOvfCreateSpec.name = $LibItemName
    $createOvfCreateSpec.description = $Description

    $libraryTemplateId = $ContentLibraryOvfService.create($UniqueChangeId,$createOvfSource,$createOvfTarget,$createOvfCreateSpec)
    
    # sleep 5 seconds so Content Library Item Attributes finish updating
    Start-Sleep -Seconds 5

    if($item_ID){
        # check to see if item updated successfully. If so, update description
        If ((get-date ($ContentLibraryService2.get($item_ID).last_modified_time)) -gt ((Get-Date).AddMinutes(-2))){

        # Update description
        $ContentLibraryItemDescUpdate = $ContentLibraryService2.Help.update.update_spec.Create()
        $ContentLibraryItemDescUpdate.description = $Description
        $ContentLibraryItemDescUpdate.id = $item_ID
        $ContentLibraryItemDescUpdate.library_id = $library_ID
        $ContentLibraryItemDescUpdateGo = $ContentLibraryService2.update($item_ID,$ContentLibraryItemDescUpdate)
        }
    }
        
    }
}
    
    