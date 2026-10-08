#global private

// Reaching a member through the type ('Wide.get') starts with a lookup that does not wait for
// the struct to complete, so it runs while another job is still registering the struct's fields.
// That lookup used to walk the field list for 'using' members and read it while it grew. The
// width of 'Wide' and the number of readers make the two jobs overlap on most runs.
struct Wide
{
    f0000, f0001, f0002, f0003, f0004, f0005, f0006, f0007, f0008, f0009, f0010, f0011, f0012, f0013, f0014, f0015: u8
    f0016, f0017, f0018, f0019, f0020, f0021, f0022, f0023, f0024, f0025, f0026, f0027, f0028, f0029, f0030, f0031: u8
    f0032, f0033, f0034, f0035, f0036, f0037, f0038, f0039, f0040, f0041, f0042, f0043, f0044, f0045, f0046, f0047: u8
    f0048, f0049, f0050, f0051, f0052, f0053, f0054, f0055, f0056, f0057, f0058, f0059, f0060, f0061, f0062, f0063: u8
    f0064, f0065, f0066, f0067, f0068, f0069, f0070, f0071, f0072, f0073, f0074, f0075, f0076, f0077, f0078, f0079: u8
    f0080, f0081, f0082, f0083, f0084, f0085, f0086, f0087, f0088, f0089, f0090, f0091, f0092, f0093, f0094, f0095: u8
    f0096, f0097, f0098, f0099, f0100, f0101, f0102, f0103, f0104, f0105, f0106, f0107, f0108, f0109, f0110, f0111: u8
    f0112, f0113, f0114, f0115, f0116, f0117, f0118, f0119, f0120, f0121, f0122, f0123, f0124, f0125, f0126, f0127: u8
    f0128, f0129, f0130, f0131, f0132, f0133, f0134, f0135, f0136, f0137, f0138, f0139, f0140, f0141, f0142, f0143: u8
    f0144, f0145, f0146, f0147, f0148, f0149, f0150, f0151, f0152, f0153, f0154, f0155, f0156, f0157, f0158, f0159: u8
    f0160, f0161, f0162, f0163, f0164, f0165, f0166, f0167, f0168, f0169, f0170, f0171, f0172, f0173, f0174, f0175: u8
    f0176, f0177, f0178, f0179, f0180, f0181, f0182, f0183, f0184, f0185, f0186, f0187, f0188, f0189, f0190, f0191: u8
    f0192, f0193, f0194, f0195, f0196, f0197, f0198, f0199, f0200, f0201, f0202, f0203, f0204, f0205, f0206, f0207: u8
    f0208, f0209, f0210, f0211, f0212, f0213, f0214, f0215, f0216, f0217, f0218, f0219, f0220, f0221, f0222, f0223: u8
    f0224, f0225, f0226, f0227, f0228, f0229, f0230, f0231, f0232, f0233, f0234, f0235, f0236, f0237, f0238, f0239: u8
    f0240, f0241, f0242, f0243, f0244, f0245, f0246, f0247, f0248, f0249, f0250, f0251, f0252, f0253, f0254, f0255: u8
    f0256, f0257, f0258, f0259, f0260, f0261, f0262, f0263, f0264, f0265, f0266, f0267, f0268, f0269, f0270, f0271: u8
    f0272, f0273, f0274, f0275, f0276, f0277, f0278, f0279, f0280, f0281, f0282, f0283, f0284, f0285, f0286, f0287: u8
    f0288, f0289, f0290, f0291, f0292, f0293, f0294, f0295, f0296, f0297, f0298, f0299, f0300, f0301, f0302, f0303: u8
    f0304, f0305, f0306, f0307, f0308, f0309, f0310, f0311, f0312, f0313, f0314, f0315, f0316, f0317, f0318, f0319: u8
    f0320, f0321, f0322, f0323, f0324, f0325, f0326, f0327, f0328, f0329, f0330, f0331, f0332, f0333, f0334, f0335: u8
    f0336, f0337, f0338, f0339, f0340, f0341, f0342, f0343, f0344, f0345, f0346, f0347, f0348, f0349, f0350, f0351: u8
    f0352, f0353, f0354, f0355, f0356, f0357, f0358, f0359, f0360, f0361, f0362, f0363, f0364, f0365, f0366, f0367: u8
    f0368, f0369, f0370, f0371, f0372, f0373, f0374, f0375, f0376, f0377, f0378, f0379, f0380, f0381, f0382, f0383: u8
    f0384, f0385, f0386, f0387, f0388, f0389, f0390, f0391, f0392, f0393, f0394, f0395, f0396, f0397, f0398, f0399: u8
    f0400, f0401, f0402, f0403, f0404, f0405, f0406, f0407, f0408, f0409, f0410, f0411, f0412, f0413, f0414, f0415: u8
    f0416, f0417, f0418, f0419, f0420, f0421, f0422, f0423, f0424, f0425, f0426, f0427, f0428, f0429, f0430, f0431: u8
    f0432, f0433, f0434, f0435, f0436, f0437, f0438, f0439, f0440, f0441, f0442, f0443, f0444, f0445, f0446, f0447: u8
    f0448, f0449, f0450, f0451, f0452, f0453, f0454, f0455, f0456, f0457, f0458, f0459, f0460, f0461, f0462, f0463: u8
    f0464, f0465, f0466, f0467, f0468, f0469, f0470, f0471, f0472, f0473, f0474, f0475, f0476, f0477, f0478, f0479: u8
    f0480, f0481, f0482, f0483, f0484, f0485, f0486, f0487, f0488, f0489, f0490, f0491, f0492, f0493, f0494, f0495: u8
    f0496, f0497, f0498, f0499, f0500, f0501, f0502, f0503, f0504, f0505, f0506, f0507, f0508, f0509, f0510, f0511: u8
    f0512, f0513, f0514, f0515, f0516, f0517, f0518, f0519, f0520, f0521, f0522, f0523, f0524, f0525, f0526, f0527: u8
    f0528, f0529, f0530, f0531, f0532, f0533, f0534, f0535, f0536, f0537, f0538, f0539, f0540, f0541, f0542, f0543: u8
    f0544, f0545, f0546, f0547, f0548, f0549, f0550, f0551, f0552, f0553, f0554, f0555, f0556, f0557, f0558, f0559: u8
    f0560, f0561, f0562, f0563, f0564, f0565, f0566, f0567, f0568, f0569, f0570, f0571, f0572, f0573, f0574, f0575: u8
    f0576, f0577, f0578, f0579, f0580, f0581, f0582, f0583, f0584, f0585, f0586, f0587, f0588, f0589, f0590, f0591: u8
    f0592, f0593, f0594, f0595, f0596, f0597, f0598, f0599, f0600, f0601, f0602, f0603, f0604, f0605, f0606, f0607: u8
    f0608, f0609, f0610, f0611, f0612, f0613, f0614, f0615, f0616, f0617, f0618, f0619, f0620, f0621, f0622, f0623: u8
    f0624, f0625, f0626, f0627, f0628, f0629, f0630, f0631, f0632, f0633, f0634, f0635, f0636, f0637, f0638, f0639: u8
    f0640, f0641, f0642, f0643, f0644, f0645, f0646, f0647, f0648, f0649, f0650, f0651, f0652, f0653, f0654, f0655: u8
    f0656, f0657, f0658, f0659, f0660, f0661, f0662, f0663, f0664, f0665, f0666, f0667, f0668, f0669, f0670, f0671: u8
    f0672, f0673, f0674, f0675, f0676, f0677, f0678, f0679, f0680, f0681, f0682, f0683, f0684, f0685, f0686, f0687: u8
    f0688, f0689, f0690, f0691, f0692, f0693, f0694, f0695, f0696, f0697, f0698, f0699, f0700, f0701, f0702, f0703: u8
    f0704, f0705, f0706, f0707, f0708, f0709, f0710, f0711, f0712, f0713, f0714, f0715, f0716, f0717, f0718, f0719: u8
    f0720, f0721, f0722, f0723, f0724, f0725, f0726, f0727, f0728, f0729, f0730, f0731, f0732, f0733, f0734, f0735: u8
    f0736, f0737, f0738, f0739, f0740, f0741, f0742, f0743, f0744, f0745, f0746, f0747, f0748, f0749, f0750, f0751: u8
    f0752, f0753, f0754, f0755, f0756, f0757, f0758, f0759, f0760, f0761, f0762, f0763, f0764, f0765, f0766, f0767: u8
    f0768, f0769, f0770, f0771, f0772, f0773, f0774, f0775, f0776, f0777, f0778, f0779, f0780, f0781, f0782, f0783: u8
    f0784, f0785, f0786, f0787, f0788, f0789, f0790, f0791, f0792, f0793, f0794, f0795, f0796, f0797, f0798, f0799: u8
    f0800, f0801, f0802, f0803, f0804, f0805, f0806, f0807, f0808, f0809, f0810, f0811, f0812, f0813, f0814, f0815: u8
    f0816, f0817, f0818, f0819, f0820, f0821, f0822, f0823, f0824, f0825, f0826, f0827, f0828, f0829, f0830, f0831: u8
    f0832, f0833, f0834, f0835, f0836, f0837, f0838, f0839, f0840, f0841, f0842, f0843, f0844, f0845, f0846, f0847: u8
    f0848, f0849, f0850, f0851, f0852, f0853, f0854, f0855, f0856, f0857, f0858, f0859, f0860, f0861, f0862, f0863: u8
    f0864, f0865, f0866, f0867, f0868, f0869, f0870, f0871, f0872, f0873, f0874, f0875, f0876, f0877, f0878, f0879: u8
    f0880, f0881, f0882, f0883, f0884, f0885, f0886, f0887, f0888, f0889, f0890, f0891, f0892, f0893, f0894, f0895: u8
    f0896, f0897, f0898, f0899, f0900, f0901, f0902, f0903, f0904, f0905, f0906, f0907, f0908, f0909, f0910, f0911: u8
    f0912, f0913, f0914, f0915, f0916, f0917, f0918, f0919, f0920, f0921, f0922, f0923, f0924, f0925, f0926, f0927: u8
    f0928, f0929, f0930, f0931, f0932, f0933, f0934, f0935, f0936, f0937, f0938, f0939, f0940, f0941, f0942, f0943: u8
    f0944, f0945, f0946, f0947, f0948, f0949, f0950, f0951, f0952, f0953, f0954, f0955, f0956, f0957, f0958, f0959: u8
    f0960, f0961, f0962, f0963, f0964, f0965, f0966, f0967, f0968, f0969, f0970, f0971, f0972, f0973, f0974, f0975: u8
    f0976, f0977, f0978, f0979, f0980, f0981, f0982, f0983, f0984, f0985, f0986, f0987, f0988, f0989, f0990, f0991: u8
    f0992, f0993, f0994, f0995, f0996, f0997, f0998, f0999, f1000, f1001, f1002, f1003, f1004, f1005, f1006, f1007: u8
    f1008, f1009, f1010, f1011, f1012, f1013, f1014, f1015, f1016, f1017, f1018, f1019, f1020, f1021, f1022, f1023: u8
    f1024, f1025, f1026, f1027, f1028, f1029, f1030, f1031, f1032, f1033, f1034, f1035, f1036, f1037, f1038, f1039: u8
    f1040, f1041, f1042, f1043, f1044, f1045, f1046, f1047, f1048, f1049, f1050, f1051, f1052, f1053, f1054, f1055: u8
    f1056, f1057, f1058, f1059, f1060, f1061, f1062, f1063, f1064, f1065, f1066, f1067, f1068, f1069, f1070, f1071: u8
    f1072, f1073, f1074, f1075, f1076, f1077, f1078, f1079, f1080, f1081, f1082, f1083, f1084, f1085, f1086, f1087: u8
    f1088, f1089, f1090, f1091, f1092, f1093, f1094, f1095, f1096, f1097, f1098, f1099, f1100, f1101, f1102, f1103: u8
    f1104, f1105, f1106, f1107, f1108, f1109, f1110, f1111, f1112, f1113, f1114, f1115, f1116, f1117, f1118, f1119: u8
    f1120, f1121, f1122, f1123, f1124, f1125, f1126, f1127, f1128, f1129, f1130, f1131, f1132, f1133, f1134, f1135: u8
    f1136, f1137, f1138, f1139, f1140, f1141, f1142, f1143, f1144, f1145, f1146, f1147, f1148, f1149, f1150, f1151: u8
    f1152, f1153, f1154, f1155, f1156, f1157, f1158, f1159, f1160, f1161, f1162, f1163, f1164, f1165, f1166, f1167: u8
    f1168, f1169, f1170, f1171, f1172, f1173, f1174, f1175, f1176, f1177, f1178, f1179, f1180, f1181, f1182, f1183: u8
    f1184, f1185, f1186, f1187, f1188, f1189, f1190, f1191, f1192, f1193, f1194, f1195, f1196, f1197, f1198, f1199: u8
    f1200, f1201, f1202, f1203, f1204, f1205, f1206, f1207, f1208, f1209, f1210, f1211, f1212, f1213, f1214, f1215: u8
    f1216, f1217, f1218, f1219, f1220, f1221, f1222, f1223, f1224, f1225, f1226, f1227, f1228, f1229, f1230, f1231: u8
    f1232, f1233, f1234, f1235, f1236, f1237, f1238, f1239, f1240, f1241, f1242, f1243, f1244, f1245, f1246, f1247: u8
    f1248, f1249, f1250, f1251, f1252, f1253, f1254, f1255, f1256, f1257, f1258, f1259, f1260, f1261, f1262, f1263: u8
    f1264, f1265, f1266, f1267, f1268, f1269, f1270, f1271, f1272, f1273, f1274, f1275, f1276, f1277, f1278, f1279: u8
    f1280, f1281, f1282, f1283, f1284, f1285, f1286, f1287, f1288, f1289, f1290, f1291, f1292, f1293, f1294, f1295: u8
    f1296, f1297, f1298, f1299, f1300, f1301, f1302, f1303, f1304, f1305, f1306, f1307, f1308, f1309, f1310, f1311: u8
    f1312, f1313, f1314, f1315, f1316, f1317, f1318, f1319, f1320, f1321, f1322, f1323, f1324, f1325, f1326, f1327: u8
    f1328, f1329, f1330, f1331, f1332, f1333, f1334, f1335, f1336, f1337, f1338, f1339, f1340, f1341, f1342, f1343: u8
    f1344, f1345, f1346, f1347, f1348, f1349, f1350, f1351, f1352, f1353, f1354, f1355, f1356, f1357, f1358, f1359: u8
    f1360, f1361, f1362, f1363, f1364, f1365, f1366, f1367, f1368, f1369, f1370, f1371, f1372, f1373, f1374, f1375: u8
    f1376, f1377, f1378, f1379, f1380, f1381, f1382, f1383, f1384, f1385, f1386, f1387, f1388, f1389, f1390, f1391: u8
    f1392, f1393, f1394, f1395, f1396, f1397, f1398, f1399, f1400, f1401, f1402, f1403, f1404, f1405, f1406, f1407: u8
    f1408, f1409, f1410, f1411, f1412, f1413, f1414, f1415, f1416, f1417, f1418, f1419, f1420, f1421, f1422, f1423: u8
    f1424, f1425, f1426, f1427, f1428, f1429, f1430, f1431, f1432, f1433, f1434, f1435, f1436, f1437, f1438, f1439: u8
    f1440, f1441, f1442, f1443, f1444, f1445, f1446, f1447, f1448, f1449, f1450, f1451, f1452, f1453, f1454, f1455: u8
    f1456, f1457, f1458, f1459, f1460, f1461, f1462, f1463, f1464, f1465, f1466, f1467, f1468, f1469, f1470, f1471: u8
    f1472, f1473, f1474, f1475, f1476, f1477, f1478, f1479, f1480, f1481, f1482, f1483, f1484, f1485, f1486, f1487: u8
    f1488, f1489, f1490, f1491, f1492, f1493, f1494, f1495, f1496, f1497, f1498, f1499, f1500, f1501, f1502, f1503: u8
    f1504, f1505, f1506, f1507, f1508, f1509, f1510, f1511, f1512, f1513, f1514, f1515, f1516, f1517, f1518, f1519: u8
    f1520, f1521, f1522, f1523, f1524, f1525, f1526, f1527, f1528, f1529, f1530, f1531, f1532, f1533, f1534, f1535: u8
    f1536, f1537, f1538, f1539, f1540, f1541, f1542, f1543, f1544, f1545, f1546, f1547, f1548, f1549, f1550, f1551: u8
    f1552, f1553, f1554, f1555, f1556, f1557, f1558, f1559, f1560, f1561, f1562, f1563, f1564, f1565, f1566, f1567: u8
    f1568, f1569, f1570, f1571, f1572, f1573, f1574, f1575, f1576, f1577, f1578, f1579, f1580, f1581, f1582, f1583: u8
    f1584, f1585, f1586, f1587, f1588, f1589, f1590, f1591, f1592, f1593, f1594, f1595, f1596, f1597, f1598, f1599: u8
}

impl Wide
{
    func get(x: s32)->s32 => x + 1
}

func reader000() => Wide.get(0); func reader001() => Wide.get(1); func reader002() => Wide.get(2); func reader003() => Wide.get(3)
func reader004() => Wide.get(4); func reader005() => Wide.get(5); func reader006() => Wide.get(6); func reader007() => Wide.get(7)
func reader008() => Wide.get(8); func reader009() => Wide.get(9); func reader010() => Wide.get(10); func reader011() => Wide.get(11)
func reader012() => Wide.get(12); func reader013() => Wide.get(13); func reader014() => Wide.get(14); func reader015() => Wide.get(15)
func reader016() => Wide.get(16); func reader017() => Wide.get(17); func reader018() => Wide.get(18); func reader019() => Wide.get(19)
func reader020() => Wide.get(20); func reader021() => Wide.get(21); func reader022() => Wide.get(22); func reader023() => Wide.get(23)
func reader024() => Wide.get(24); func reader025() => Wide.get(25); func reader026() => Wide.get(26); func reader027() => Wide.get(27)
func reader028() => Wide.get(28); func reader029() => Wide.get(29); func reader030() => Wide.get(30); func reader031() => Wide.get(31)
func reader032() => Wide.get(32); func reader033() => Wide.get(33); func reader034() => Wide.get(34); func reader035() => Wide.get(35)
func reader036() => Wide.get(36); func reader037() => Wide.get(37); func reader038() => Wide.get(38); func reader039() => Wide.get(39)
func reader040() => Wide.get(40); func reader041() => Wide.get(41); func reader042() => Wide.get(42); func reader043() => Wide.get(43)
func reader044() => Wide.get(44); func reader045() => Wide.get(45); func reader046() => Wide.get(46); func reader047() => Wide.get(47)
func reader048() => Wide.get(48); func reader049() => Wide.get(49); func reader050() => Wide.get(50); func reader051() => Wide.get(51)
func reader052() => Wide.get(52); func reader053() => Wide.get(53); func reader054() => Wide.get(54); func reader055() => Wide.get(55)
func reader056() => Wide.get(56); func reader057() => Wide.get(57); func reader058() => Wide.get(58); func reader059() => Wide.get(59)
func reader060() => Wide.get(60); func reader061() => Wide.get(61); func reader062() => Wide.get(62); func reader063() => Wide.get(63)
func reader064() => Wide.get(64); func reader065() => Wide.get(65); func reader066() => Wide.get(66); func reader067() => Wide.get(67)
func reader068() => Wide.get(68); func reader069() => Wide.get(69); func reader070() => Wide.get(70); func reader071() => Wide.get(71)
func reader072() => Wide.get(72); func reader073() => Wide.get(73); func reader074() => Wide.get(74); func reader075() => Wide.get(75)
func reader076() => Wide.get(76); func reader077() => Wide.get(77); func reader078() => Wide.get(78); func reader079() => Wide.get(79)
func reader080() => Wide.get(80); func reader081() => Wide.get(81); func reader082() => Wide.get(82); func reader083() => Wide.get(83)
func reader084() => Wide.get(84); func reader085() => Wide.get(85); func reader086() => Wide.get(86); func reader087() => Wide.get(87)
func reader088() => Wide.get(88); func reader089() => Wide.get(89); func reader090() => Wide.get(90); func reader091() => Wide.get(91)
func reader092() => Wide.get(92); func reader093() => Wide.get(93); func reader094() => Wide.get(94); func reader095() => Wide.get(95)
func reader096() => Wide.get(96); func reader097() => Wide.get(97); func reader098() => Wide.get(98); func reader099() => Wide.get(99)
func reader100() => Wide.get(100); func reader101() => Wide.get(101); func reader102() => Wide.get(102); func reader103() => Wide.get(103)
func reader104() => Wide.get(104); func reader105() => Wide.get(105); func reader106() => Wide.get(106); func reader107() => Wide.get(107)
func reader108() => Wide.get(108); func reader109() => Wide.get(109); func reader110() => Wide.get(110); func reader111() => Wide.get(111)
func reader112() => Wide.get(112); func reader113() => Wide.get(113); func reader114() => Wide.get(114); func reader115() => Wide.get(115)
func reader116() => Wide.get(116); func reader117() => Wide.get(117); func reader118() => Wide.get(118); func reader119() => Wide.get(119)
func reader120() => Wide.get(120); func reader121() => Wide.get(121); func reader122() => Wide.get(122); func reader123() => Wide.get(123)
func reader124() => Wide.get(124); func reader125() => Wide.get(125); func reader126() => Wide.get(126); func reader127() => Wide.get(127)
func reader128() => Wide.get(128); func reader129() => Wide.get(129); func reader130() => Wide.get(130); func reader131() => Wide.get(131)
func reader132() => Wide.get(132); func reader133() => Wide.get(133); func reader134() => Wide.get(134); func reader135() => Wide.get(135)
func reader136() => Wide.get(136); func reader137() => Wide.get(137); func reader138() => Wide.get(138); func reader139() => Wide.get(139)
func reader140() => Wide.get(140); func reader141() => Wide.get(141); func reader142() => Wide.get(142); func reader143() => Wide.get(143)
func reader144() => Wide.get(144); func reader145() => Wide.get(145); func reader146() => Wide.get(146); func reader147() => Wide.get(147)
func reader148() => Wide.get(148); func reader149() => Wide.get(149); func reader150() => Wide.get(150); func reader151() => Wide.get(151)
func reader152() => Wide.get(152); func reader153() => Wide.get(153); func reader154() => Wide.get(154); func reader155() => Wide.get(155)
func reader156() => Wide.get(156); func reader157() => Wide.get(157); func reader158() => Wide.get(158); func reader159() => Wide.get(159)
func reader160() => Wide.get(160); func reader161() => Wide.get(161); func reader162() => Wide.get(162); func reader163() => Wide.get(163)
func reader164() => Wide.get(164); func reader165() => Wide.get(165); func reader166() => Wide.get(166); func reader167() => Wide.get(167)
func reader168() => Wide.get(168); func reader169() => Wide.get(169); func reader170() => Wide.get(170); func reader171() => Wide.get(171)
func reader172() => Wide.get(172); func reader173() => Wide.get(173); func reader174() => Wide.get(174); func reader175() => Wide.get(175)
func reader176() => Wide.get(176); func reader177() => Wide.get(177); func reader178() => Wide.get(178); func reader179() => Wide.get(179)
func reader180() => Wide.get(180); func reader181() => Wide.get(181); func reader182() => Wide.get(182); func reader183() => Wide.get(183)
func reader184() => Wide.get(184); func reader185() => Wide.get(185); func reader186() => Wide.get(186); func reader187() => Wide.get(187)
func reader188() => Wide.get(188); func reader189() => Wide.get(189); func reader190() => Wide.get(190); func reader191() => Wide.get(191)
func reader192() => Wide.get(192); func reader193() => Wide.get(193); func reader194() => Wide.get(194); func reader195() => Wide.get(195)
func reader196() => Wide.get(196); func reader197() => Wide.get(197); func reader198() => Wide.get(198); func reader199() => Wide.get(199)
func reader200() => Wide.get(200); func reader201() => Wide.get(201); func reader202() => Wide.get(202); func reader203() => Wide.get(203)
func reader204() => Wide.get(204); func reader205() => Wide.get(205); func reader206() => Wide.get(206); func reader207() => Wide.get(207)
func reader208() => Wide.get(208); func reader209() => Wide.get(209); func reader210() => Wide.get(210); func reader211() => Wide.get(211)
func reader212() => Wide.get(212); func reader213() => Wide.get(213); func reader214() => Wide.get(214); func reader215() => Wide.get(215)
func reader216() => Wide.get(216); func reader217() => Wide.get(217); func reader218() => Wide.get(218); func reader219() => Wide.get(219)
func reader220() => Wide.get(220); func reader221() => Wide.get(221); func reader222() => Wide.get(222); func reader223() => Wide.get(223)
func reader224() => Wide.get(224); func reader225() => Wide.get(225); func reader226() => Wide.get(226); func reader227() => Wide.get(227)
func reader228() => Wide.get(228); func reader229() => Wide.get(229); func reader230() => Wide.get(230); func reader231() => Wide.get(231)
func reader232() => Wide.get(232); func reader233() => Wide.get(233); func reader234() => Wide.get(234); func reader235() => Wide.get(235)
func reader236() => Wide.get(236); func reader237() => Wide.get(237); func reader238() => Wide.get(238); func reader239() => Wide.get(239)
func reader240() => Wide.get(240); func reader241() => Wide.get(241); func reader242() => Wide.get(242); func reader243() => Wide.get(243)
func reader244() => Wide.get(244); func reader245() => Wide.get(245); func reader246() => Wide.get(246); func reader247() => Wide.get(247)
func reader248() => Wide.get(248); func reader249() => Wide.get(249); func reader250() => Wide.get(250); func reader251() => Wide.get(251)
func reader252() => Wide.get(252); func reader253() => Wide.get(253); func reader254() => Wide.get(254); func reader255() => Wide.get(255)

#assert(#sizeof(Wide) == 1600)
#assert(Wide.get(41) == 42)
