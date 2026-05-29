import 'package:judge_matrixse_app/data_structures/column_role.dart';

class ColumnSpec {
  final String nameInFile;
  String? mappedName;
  ColumnRole role;
  String dtype;
  bool required;
  Map<String, dynamic> toJson() => {
        'name_in_file': nameInFile,
        'mapped_name': mappedName ?? nameInFile,
        'role': role.name.toUpperCase(),
        'dtype': dtype,
        'required': required,
      };
      
  ColumnSpec({required this.nameInFile, this.mappedName, this.role = ColumnRole.feature, this.dtype = 'string', this.required = false});
  
}