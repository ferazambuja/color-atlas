function XYZ=cvd_adapter(mode,xyz,white)
switch string(mode)
    case "protanopia",key="protan";
    case "deuteranopia",key="deutan";
    case "tritanopia",key="tritan";
    otherwise,error('Unknown fixture mode %s',mode);
end
XYZ=ColorAtlasScience.simulateDichromat(key,xyz,white);
end
