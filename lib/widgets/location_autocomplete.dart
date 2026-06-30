import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../services/location_search_service.dart';

class LocationAutocomplete extends StatefulWidget {
  const LocationAutocomplete({
    super.key,
    required this.controller,
    required this.onLocationSelected,
    this.hint = 'Search location',
    this.icon = Icons.location_on,
    this.iconColor = const Color(0xFF00897B),
    this.label = 'Location',
  });

  final TextEditingController controller;
  final Function(LatLng coordinates, String displayName) onLocationSelected;
  final String hint;
  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  State<LocationAutocomplete> createState() => _LocationAutocompleteState();
}

class _LocationAutocompleteState extends State<LocationAutocomplete> {
  List<LocationSuggestion> _suggestions = [];
  bool _isLoading = false;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    if (text.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    if (text.length >= 3) {
      _searchLocations(text);
    }
  }

  Future<void> _searchLocations(String query) async {
    setState(() {
      _isLoading = true;
      _showSuggestions = true;
    });

    final results = await LocationSearchService.searchLocations(query);

    if (mounted) {
      setState(() {
        _suggestions = results;
        _isLoading = false;
      });
    }
  }

  void _selectSuggestion(LocationSuggestion suggestion) {
    widget.controller.text = suggestion.description;
    widget.onLocationSelected(suggestion.coordinates, suggestion.description);
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF1F4F7),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: widget.iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.label,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      TextField(
                        controller: widget.controller,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF212121)),
                        decoration: InputDecoration(
                          hintText: widget.hint,
                          hintStyle: TextStyle(
                              fontSize: 13, color: Colors.grey.shade400),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      widget.controller.clear();
                      setState(() {
                        _suggestions = [];
                        _showSuggestions = false;
                      });
                    },
                    child: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),
        ),
        if (_showSuggestions)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00897B)),
                      ),
                    ),
                  )
                : _suggestions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No locations found',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _suggestions.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          color: Colors.grey.shade200,
                          indent: 16,
                          endIndent: 16,
                        ),
                        itemBuilder: (context, index) {
                          final suggestion = _suggestions[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: const Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: Color(0xFF00897B),
                            ),
                            title: Text(
                              suggestion.description,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF212121),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectSuggestion(suggestion),
                          );
                        },
                      ),
          ),
      ],
    );
  }
}
