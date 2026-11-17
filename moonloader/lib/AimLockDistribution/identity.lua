local Identity={author='IronForgez | Arvin_Inc',version='1.5.1'}

function Identity.display(value)
    -- A local keeps gsub's replacement count out of callers after minification.
    local text=tostring(value or ''):gsub('aimlock_enabled','tracking_enabled')
        :gsub('[Aa][Ii][Mm][Ll][Oo][Cc][Kk]','Panel')
    return text
end
function Identity.message(value)
    return '['..Identity.author..'] '..Identity.display(value)
end
function Identity.log_label(path)
    return Identity.display(path and path:match('[^/\\]+$') or 'Pilih log')
end
return Identity
