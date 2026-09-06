import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nexodine/core/theme/app_colors.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/database/database_helper.dart';

class RecipeManagementScreen extends StatefulWidget {
  final Map<String, dynamic> product;

  const RecipeManagementScreen({super.key, required this.product});

  @override
  State<RecipeManagementScreen> createState() => _RecipeManagementScreenState();
}

class _RecipeManagementScreenState extends State<RecipeManagementScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers for preparation details
  final _prepTimeController = TextEditingController();
  final _cookTimeController = TextEditingController();
  final _servingsController = TextEditingController();
  String _difficulty = 'Easy';

  // Recipe steps and ingredients
  final _stepController = TextEditingController();
  final _recipeQtyController = TextEditingController();

  List<String> _steps = [];
  List<Map<String, dynamic>> _localRecipe = [];
  List<Map<String, dynamic>> _allIngredients = [];
  int? _selectedIngredientId;

  // Video Tutorial
  String? _videoPath;
  VideoPlayerController? _videoPlayerController;
  bool _isPlayerInitialized = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecipeData();
  }

  Future<void> _loadRecipeData() async {
    final db = await DatabaseHelper.instance.database;
    final productId = widget.product['id'];

    // 1. Fetch raw ingredients list for dropdown
    _allIngredients = await db.query('inventory', orderBy: 'item_name ASC');

    // 2. Fetch existing product record to get prep details and video path
    final productList = await db.query('products', where: 'id = ?', whereArgs: [productId]);
    if (productList.isNotEmpty) {
      final productData = productList.first;
      _prepTimeController.text = (productData['prep_time'] ?? '').toString();
      _cookTimeController.text = (productData['cook_time'] ?? '').toString();
      _servingsController.text = (productData['servings'] ?? '').toString();
      _difficulty = productData['difficulty'] as String? ?? 'Easy';
      _videoPath = productData['video_path'] as String?;

      final stepsStr = productData['recipe_steps'] as String? ?? '';
      _steps = stepsStr.split('\n').where((s) => s.trim().isNotEmpty).toList();
    }

    // 3. Fetch linked ingredients from recipes table
    final recipeItems = await db.rawQuery('''
      SELECT recipes.*, inventory.item_name as ingredient_name, inventory.unit 
      FROM recipes 
      JOIN inventory ON recipes.ingredient_id = inventory.id 
      WHERE recipes.product_id = ?
    ''', [productId]);

    _localRecipe = recipeItems.map((item) => {
      'ingredient_id': item['ingredient_id'],
      'ingredient_name': item['ingredient_name'],
      'quantity_used': item['quantity_used'],
      'unit': item['unit'] ?? '',
    }).toList();

    // 4. Initialize video player if path exists
    if (_videoPath != null && _videoPath!.isNotEmpty) {
      _initializeVideoPlayer();
    }

    setState(() => _isLoading = false);
  }

  void _initializeVideoPlayer() {
    if (_videoPath == null) return;
    final file = File(_videoPath!);
    if (!file.existsSync()) return;

    _videoPlayerController?.dispose();
    _videoPlayerController = VideoPlayerController.file(file)
      ..initialize().then((_) {
        setState(() {
          _isPlayerInitialized = true;
        });
      });
  }

  Future<void> _pickVideo() async {
    try {
      final result = await fp.FilePicker.pickFiles(
        type: fp.FileType.video,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _videoPath = result.files.single.path;
          _isPlayerInitialized = false;
        });
        _initializeVideoPlayer();
      }
    } catch (e) {

    }
  }

  void _removeVideo() {
    setState(() {
      _videoPath = null;
      _videoPlayerController?.dispose();
      _videoPlayerController = null;
      _isPlayerInitialized = false;
    });
  }

  Future<void> _openInSystemPlayer() async {
    if (_videoPath != null) {
      final uri = Uri.file(_videoPath!);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {

      }
    }
  }

  Future<void> _saveRecipe() async {
    if (!_formKey.currentState!.validate()) return;

    final db = await DatabaseHelper.instance.database;
    final productId = widget.product['id'] as int;

    // Collect all ingredient names to sync back to the main products.ingredients field
    final ingredientNames = _localRecipe.map((e) => e['ingredient_name'] as String).toList();
    
    // Add any manual ingredients already defined
    final manualIngsStr = widget.product['ingredients'] as String? ?? '';
    final manualIngs = manualIngsStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final combinedIngredients = {...ingredientNames, ...manualIngs}.join(',');

    final prepTime = int.tryParse(_prepTimeController.text.trim());
    final cookTime = int.tryParse(_cookTimeController.text.trim());
    final servings = int.tryParse(_servingsController.text.trim());

    // 1. Update product detail columns
    await db.update(
      'products',
      {
        'prep_time': prepTime,
        'cook_time': cookTime,
        'servings': servings,
        'difficulty': _difficulty,
        'video_path': _videoPath,
        'recipe_steps': _steps.join('\n'),
        'ingredients': combinedIngredients,
      },
      where: 'id = ?',
      whereArgs: [productId],
    );

    // 2. Sync recipes ingredient table
    await db.delete('recipes', where: 'product_id = ?', whereArgs: [productId]);
    for (var rItem in _localRecipe) {
      await db.insert('recipes', {
        'product_id': productId,
        'ingredient_id': rItem['ingredient_id'],
        'quantity_used': rItem['quantity_used'],
      });
    }

    if (mounted) {

      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _prepTimeController.dispose();
    _cookTimeController.dispose();
    _servingsController.dispose();
    _stepController.dispose();
    _recipeQtyController.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      appBar: AppBar(
        title: Text('Recipe Management: ${widget.product['name']}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            // tooltip disabled,
            onPressed: _saveRecipe,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
            ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column (Prep Details, Instructions, Video)
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPrepDetailsSection(),
                const SizedBox(height: 20),
                _buildVideoSection(),
                const SizedBox(height: 20),
                _buildInstructionsSection(),
              ],
            ),
          ),
        ),
        // Vertical Divider
        VerticalDivider(width: 1, color: Colors.grey.shade300),
        // Right Column (Ingredients Linking)
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildIngredientsSection(),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPrepDetailsSection(),
          const SizedBox(height: 20),
          _buildVideoSection(),
          const SizedBox(height: 20),
          _buildIngredientsSection(),
          const SizedBox(height: 20),
          _buildInstructionsSection(),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text('Save Recipe', style: TextStyle(fontSize: 16, color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _saveRecipe,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrepDetailsSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Preparation Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _prepTimeController,
                    decoration: const InputDecoration(
                      labelText: 'Prep Time (mins)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _cookTimeController,
                    decoration: const InputDecoration(
                      labelText: 'Cook Time (mins)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _servingsController,
                    decoration: const InputDecoration(
                      labelText: 'Servings',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _difficulty,
                    decoration: const InputDecoration(
                      labelText: 'Difficulty',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: ['Easy', 'Medium', 'Hard'].map((lvl) => DropdownMenuItem(
                      value: lvl,
                      child: Text(lvl),
                    )).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _difficulty = val);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSection() {
    final player = _videoPlayerController;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recipe Tutorial Video',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
                if (_videoPath != null)
                  TextButton.icon(
                    icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                    label: const Text('Remove Video', style: TextStyle(color: Colors.red)),
                    onPressed: _removeVideo,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_videoPath == null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.video_library_outlined, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('No tutorial video uploaded', style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file, color: Colors.white),
                      label: const Text('Select Video File', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: _pickVideo,
                    ),
                  ],
                ),
              )
            else ...[
              Text(
                'File: ${Platform.isWindows ? _videoPath : _videoPath!.split('/').last}',
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              if (_isPlayerInitialized && player != null) ...[
                AspectRatio(
                  aspectRatio: player.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      VideoPlayer(player),
                      _VideoControlsOverlay(controller: player),
                      VideoProgressIndicator(player, allowScrubbing: true),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ] else
                Container(
                  height: 150,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Initializing video player...', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in System Player'),
                    onPressed: _openInSystemPlayer,
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Change Video'),
                    onPressed: _pickVideo,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIngredientsSection() {
    // Filter out already selected ingredients
    final availableIngs = _allIngredients.where((ing) =>
      !_localRecipe.any((item) => item['ingredient_id'] == ing['id'])
    ).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recipe Ingredients',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<int>(
                    value: _selectedIngredientId,
                    decoration: const InputDecoration(
                      labelText: 'Select Ingredient',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: availableIngs.map((ing) => DropdownMenuItem<int>(
                      value: ing['id'] as int,
                      child: Text('${ing['item_name']} (${ing['unit']})'),
                    )).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedIngredientId = val;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _recipeQtyController,
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.primary, size: 36),
                  onPressed: () {
                    if (_selectedIngredientId != null && _recipeQtyController.text.isNotEmpty) {
                      final qty = double.tryParse(_recipeQtyController.text);
                      if (qty != null && qty > 0) {
                        final selectedIng = _allIngredients.firstWhere((ing) => ing['id'] == _selectedIngredientId);
                        setState(() {
                          _localRecipe.add({
                            'ingredient_id': _selectedIngredientId,
                            'ingredient_name': selectedIng['name'],
                            'quantity_used': qty,
                            'unit': selectedIng['unit'],
                          });
                          _selectedIngredientId = null;
                          _recipeQtyController.clear();
                        });
                      }
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _localRecipe.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No ingredients added to this recipe.', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _localRecipe.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _localRecipe[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(item['ingredient_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('Required: ${item['quantity_used']} ${item['unit']}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () {
                            setState(() {
                              _localRecipe.removeAt(index);
                              _selectedIngredientId = null;
                            });
                          },
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cooking Steps & Instructions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _stepController,
                    decoration: const InputDecoration(
                      labelText: 'Describe cooking/preparation step...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: AppColors.primary, size: 36),
                  onPressed: () {
                    final val = _stepController.text.trim();
                    if (val.isNotEmpty) {
                      setState(() {
                        _steps.add(val);
                        _stepController.clear();
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _steps.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No instructions added yet.', style: TextStyle(color: Colors.grey)),
                    ),
                  )
                : ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _steps.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final item = _steps.removeAt(oldIndex);
                        _steps.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, index) {
                      return ListTile(
                        key: ValueKey('step_$index'),
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.primaryLight,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ),
                        title: Text(_steps[index]),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.drag_handle, color: Colors.grey),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                              onPressed: () {
                                setState(() {
                                  _steps.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class _VideoControlsOverlay extends StatefulWidget {
  final VideoPlayerController controller;

  const _VideoControlsOverlay({required this.controller});

  @override
  State<_VideoControlsOverlay> createState() => _VideoControlsOverlayState();
}

class _VideoControlsOverlayState extends State<_VideoControlsOverlay> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final isPlaying = controller.value.isPlaying;

    return GestureDetector(
      onTap: () {
        setState(() {
          isPlaying ? controller.pause() : controller.play();
        });
      },
      child: Container(
        color: Colors.black26,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: isPlaying
                ? const SizedBox.shrink()
                : CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.black45,
                    child: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
