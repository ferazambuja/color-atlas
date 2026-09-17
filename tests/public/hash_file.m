function sha=hash_file(path)
% SHA-256 of actual file bytes for a retained validation record.
fid=fopen(path,'rb');assert(fid>=0);bytes=fread(fid,Inf,'*uint8');fclose(fid);
md=java.security.MessageDigest.getInstance('SHA-256');md.update(bytes);
sha=lower(reshape(dec2hex(typecast(md.digest(),'uint8'))',1,[]));
end
