import 'package:flutter/material.dart';
import 'package:judge_matrixse_app/components/glass_card.dart';
import 'package:judge_matrixse_app/data_structures/column_role.dart';
import 'package:judge_matrixse_app/data_structures/column_spec.dart';

class Mapping extends StatefulWidget {
  const Mapping({super.key, required this.columns, required this.onChanged});
  final List<ColumnSpec> columns;
  final VoidCallback onChanged;
  @override
  State<Mapping> createState() => _MappingState();
}

class _MappingState extends State<Mapping> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (c, cons) {
        final wide = cons.maxWidth > 900;
        final colWidth = wide ? (cons.maxWidth - 24) / 2 : cons.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final col in widget.columns)
              SizedBox(
                width: colWidth,
                child: GlassCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.view_column, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                col.nameInFile,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 170,
                              child: DropdownButtonFormField<ColumnRole>(
                                initialValue: col.role,
                                decoration: const InputDecoration(
                                  labelText: 'Role',
                                ),
                                items:
                                    ColumnRole.values
                                        .map(
                                          (r) => DropdownMenuItem(
                                            value: r,
                                            child: Text(r.name.toUpperCase()),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (r) {
                                  if (r == null) return;
                                  if (r == ColumnRole.id) {
                                    for (final c in widget.columns) {
                                      if (!identical(c, col) &&
                                          c.role == ColumnRole.id) {
                                        c.role = ColumnRole.feature;
                                      }
                                    }
                                  }
                                  setState(() => col.role = r);
                                  widget.onChanged();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: col.mappedName ?? col.nameInFile,
                                decoration: const InputDecoration(
                                  labelText: 'Standardized name',
                                ),
                                onChanged: (v) => col.mappedName = v,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 150,
                              child: DropdownButtonFormField<String>(
                                initialValue: col.dtype,
                                decoration: const InputDecoration(
                                  labelText: 'Type',
                                ),
                                items:
                                    [
                                          'string',
                                          'int',
                                          'float',
                                          'bool',
                                          'date',
                                          'json',
                                        ]
                                        .map(
                                          (e) => DropdownMenuItem(
                                            value: e,
                                            child: Text(e),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (v) {
                                  setState(() => col.dtype = v ?? 'string');
                                  widget.onChanged();
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Row(
                              children: [
                                const Text('Mandatory'),
                                Switch(
                                  value: col.required,
                                  onChanged: (v) {
                                    setState(() => col.required = v);
                                    widget.onChanged();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
