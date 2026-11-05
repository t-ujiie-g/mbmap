import assert from "node:assert/strict";
import test from "node:test";
import { parsePrj } from "../src/prjwkt.ts";
import { parseProjString } from "../src/projstring.ts";

const D2R = Math.PI / 180;
const IX = 139 + 50 / 60;
const ESRI_IX = `PROJCS["JGD_2011_Japan_Zone_9",GEOGCS["GCS_JGD_2011",DATUM["D_JGD_2011",SPHEROID["GRS_1980",6378137.0,298.257222101]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],PROJECTION["Transverse_Mercator"],PARAMETER["False_Easting",0.0],PARAMETER["False_Northing",0.0],PARAMETER["Central_Meridian",${IX}],PARAMETER["Scale_Factor",0.9999],PARAMETER["Latitude_Of_Origin",36.0],UNIT["Meter",1.0]]`;

test("parsePrj reads Esri WKT as proj4js does: the slots of the PROJ string it amounts to", () => {
  const { code, definition } = parsePrj(ESRI_IX);
  assert.equal(code, undefined);
  const want = parseProjString(`+proj=tmerc +lat_0=36 +lon_0=${IX} +k=0.9999 +x_0=0 +y_0=0 +a=6378137 +rf=298.257222101`);
  want[13] = 1;
  assert.deepEqual(definition, want);
});

test("parsePrj gives the root's EPSG code, with the definition, and Web Mercator by name", () => {
  const ogc = `PROJCS["WGS 84 / UTM zone 54N",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433]],PROJECTION["Transverse_Mercator"],PARAMETER["latitude_of_origin",0],PARAMETER["central_meridian",141],PARAMETER["scale_factor",0.9996],PARAMETER["false_easting",500000],PARAMETER["false_northing",0],UNIT["metre",1],AXIS["Easting",EAST],AXIS["Northing",NORTH],AUTHORITY["EPSG","32654"]]`;
  const { code, definition } = parsePrj(ogc);
  assert.equal(code, 32654);
  assert.deepEqual([definition![0], definition![4], definition![20], definition![26], definition![28]], [2, 3, 141 * D2R, 500000, 0.9996]);
  const esri3857 = `PROJCS["WGS_1984_Web_Mercator_Auxiliary_Sphere",GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],PROJECTION["Mercator_Auxiliary_Sphere"],PARAMETER["False_Easting",0.0],PARAMETER["False_Northing",0.0],PARAMETER["Central_Meridian",0.0],PARAMETER["Standard_Parallel_1",0.0],PARAMETER["Auxiliary_Sphere_Type",0.0],UNIT["Meter",1.0]]`;
  assert.equal(parsePrj(esri3857).code, 3857);
  const geog = parsePrj(`GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]`);
  assert.deepEqual([geog.definition![0], geog.definition![4], geog.definition![13]], [0, 3, NaN]);
  const towgs = parsePrj(`GEOGCS["Tokyo",DATUM["Tokyo",SPHEROID["Bessel 1841",6377397.155,299.1528128],TOWGS84[-146.414,507.337,680.507,0,0,0,0]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433],AUTHORITY["EPSG","4301"]]`);
  assert.equal(towgs.code, 4301);
  assert.deepEqual(Array.from(towgs.definition!.subarray(4, 12)), [7, -146.414, 507.337, 680.507, 0, 0, 0, 0]);
  const unknown = parsePrj(`PROJCS["x",GEOGCS["g",DATUM["d",SPHEROID["s",1,0]]],PROJECTION["Vertical_Perspective"],AUTHORITY["EPSG","5555"]]`);
  assert.deepEqual(unknown, { code: 5555 });
});

test("parsePrj refuses WKT2, other CRS types, unknown projections and malformed text", () => {
  assert.throws(() => parsePrj(`PROJCRS["x",BASEGEOGCRS["y"]]`), /WKT2 is not supported/);
  assert.throws(() => parsePrj(`GEOCCS["x"]`), /unsupported CRS type GEOCCS/);
  assert.throws(() => parsePrj(`PROJCS["x",GEOGCS["g"],PROJECTION["Vertical_Perspective"]]`), /unsupported projection Vertical_Perspective/);
  assert.throws(() => parsePrj(`GEOGCS["g",DATUM["d",SPHEROID["s",1,2],TOWGS84[1,2]]]`), /TOWGS84 takes 3 or 7 values/);
  for (const bad of [`GEOGCS["g"`, `GEOGCS["g"]]`, `"g"`, `GEOGCS["g"] GEOGCS["h"]`, `GEOGCS[@]`]) {
    assert.throws(() => parsePrj(bad), /\.prj: /);
  }
  assert.throws(() => parsePrj("GEOGCS[".repeat(40)), /nested too deep/);
});
